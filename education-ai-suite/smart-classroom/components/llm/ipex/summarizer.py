from components.llm.base_summarizer import BaseSummarizer
import torch
import threading
from utils.locks import audio_pipeline_lock
from utils.config_loader import config
from utils import ensure_model
from transformers import TextIteratorStreamer
import logging
import os
logger = logging.getLogger(__name__)
try:
    from ipex_llm.transformers import AutoModelForCausalLM
except ImportError as e:
    if(config.models.summarizer.provider == "ipex"):
        logger.error("Error importing ipex_llm. Install required dependencies or set summarizer to OpenVINO in config.yaml.")
        raise e
    AutoModelForCausalLM = None

class Summarizer(BaseSummarizer):
    def __init__(self, model_name, device="xpu", temperature=0.7):
        if config.models.summarizer.model_hub is not None:
            model_hub = config.models.summarizer.model_hub
        else:
            model_hub = "huggingface"

        if model_hub == "huggingface":
            from transformers import AutoTokenizer
        elif model_hub == "modelscope":
            from modelscope import AutoTokenizer
        else:
            raise ValueError(f"Unsupported Model Hub: {model_hub}, should be huggingface or modelscope")

        if not device.startswith("gpu") and device != "cpu":
            raise ValueError(f"Unknown device {device}")
        if device == "gpu" or device == "gpu.0":
            device = "xpu"
        elif device.startswith("gpu.") and device[4:].isdigit():
            device = f"xpu:{device[4:]}"

        # Load model
        if config.models.summarizer.use_cache is not None:
            use_cache = config.models.summarizer.use_cache
        else:
            use_cache = True

        if config.models.summarizer.weight_format and config.models.summarizer.weight_format.lower() == "int4":
            logger.info("Loading model in sym_int4 quantization mode.")
            load_in_low_bit = "sym_int4"
        elif config.models.summarizer.weight_format and config.models.summarizer.weight_format.lower() == "int8":
            logger.info("Loading model in sym_int8 quantization mode.")
            load_in_low_bit = "sym_int8"
        elif config.models.summarizer.weight_format and config.models.summarizer.weight_format.lower() == "fp16":
            logger.info("Loading model in fp16 quantization mode.")
            load_in_low_bit = "fp16"
        else:
            logger.info("Loading model in full precision mode.")
            load_in_low_bit = None

        model_dir = ensure_model.get_model_path()
        local_files_only=False
        if os.path.exists(model_dir):
            local_files_only=True

        self.model = AutoModelForCausalLM.from_pretrained(
            model_name,
            # load_in_4bit=True,
            load_in_low_bit=load_in_low_bit,
            optimize_model=True,
            trust_remote_code=True,
            use_cache=use_cache,
            model_hub=model_hub,
            cache_dir=model_dir,
            local_files_only=local_files_only
        )
        self.device = device
        self.model = self.model.to(self.device)
        self.model = self.model.eval().to(self.device)

        self.temperature = temperature

        self.tokenizer = AutoTokenizer.from_pretrained(
            model_name,
            trust_remote_code=True
        )

    def generate(self, prompt: str, stream: bool = True):
        max_new_tokens = config.models.summarizer.max_new_tokens or 1024

        with torch.inference_mode():
            model_inputs = self.tokenizer(prompt, return_tensors="pt").to(self.device)
            if not stream:
                try:
                    generated_ids = self.model.generate(
                        model_inputs.input_ids,
                        max_new_tokens=max_new_tokens,
                        temperature=self.temperature
                    )
                    torch.xpu.empty_cache()
                    torch.xpu.synchronize()
                    generated_ids = generated_ids.cpu()
                    generated_ids = [
                        output_ids[len(input_ids):] for input_ids, output_ids in zip(model_inputs.input_ids, generated_ids)
                    ]

                    response = self.tokenizer.batch_decode(generated_ids, skip_special_tokens=True)[0]
                    return response
                except Exception as e:
                    logger.error(f"Error during generation: {e}")
                    return None
            else:
                class CountingTextIteratorStreamer(TextIteratorStreamer):
                    def __init__(self, tokenizer, skip_special_tokens=True, skip_prompt=True):
                        super().__init__(tokenizer, skip_special_tokens=skip_special_tokens, skip_prompt=skip_prompt)
                        self.total_tokens = 0

                    def put(self, value):
                        self.total_tokens += 1
                        super().put(value)

                streamer = CountingTextIteratorStreamer(self.tokenizer, skip_special_tokens=True, skip_prompt=True)

                def run_generation():
                    try:
                        audio_pipeline_lock.acquire()
                        gen_kwargs = dict(
                            input_ids=model_inputs.input_ids,
                            max_new_tokens=max_new_tokens,
                            temperature=self.temperature,
                            streamer=streamer
                        )

                        torch.xpu.empty_cache()
                        torch.xpu.synchronize()

                        self.model.generate(**gen_kwargs)
                    finally:
                        audio_pipeline_lock.release()
                        streamer.end()

                threading.Thread(target=run_generation, daemon=True).start()
                return streamer
