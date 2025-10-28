# How to use CPU for inference

## CPU specific element properties

DL Streamer inference elements also provides property such as `device=CPU` and `pre-process-backend=opencv` to infer and pre-process on CPU. Read DL Streamer [docs](https://dlstreamer.github.io/dev_guide/model_preparation.html#model-pre-and-post-processing) for more.

## Tutorial on how to use CPU specific pipelines

The pipeline `pallet_defect_detection_cpu` in [pipeline-server-config](../../configs/pipeline-server-config.json) contains CPU specific elements and uses CPU backend for inferencing. We will now start the pipeline with a curl request.

```sh
curl http://<HOST_IP>:8080/pipelines/user_defined_pipelines/pallet_defect_detection_cpu -X POST -H 'Content-Type: application/json' -d '{
    "source": {
        "uri": "file:///home/pipeline-server/resources/videos/warehouse.avi",
        "type": "uri"
    },
    "destination": {
        "metadata": {
            "type": "file",
            "path": "/tmp/results.jsonl",
            "format": "json-lines"
        }
    },
    "parameters": {
        "detection-properties": {
            "model": "/home/pipeline-server/resources/models/pallet-defect-detection/deployment/Detection/model/model.xml"
        }
    }
}'
```

We should see the metadata results in `/tmp/results.jsonl` file.