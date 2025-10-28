# Configure Time Series Analytics Microservice with Custom UDF deployment package

This guide provides instructions for setting up custom UDF deployment package (UDFs, TICKscripts, models) and config.json in **Time Series Analytics Microservice**.

- **`config.json`**:
   - Understand the configuration documented at [link](get-started.md#configjson) and update 
     as per the need to configure the custom UDF deployment package

- **`UDF Deployment package`**:

  1. **`udfs/`**:
     - Contains python scripts for UDFs.
     - If additional python packages are required, list them in `requirements.txt` using pinned versions.

  2. **`tick_scripts/`**:
     - Contains TICKscripts for data processing, analytics, and alerts.
     - Mode detail on writing TICKscript is available at <https://docs.influxdata.com/kapacitor/v1/reference/tick/introduction/>
   
     - Example TICKscript:
         
      ```bash
      dbrp "datain"."autogen"

      var data0 = stream
          |from()
              .database('datain')
              .retentionPolicy('autogen')
              .measurement('opcua')
          @windturbine_anomaly_detector()
          |alert()
              .crit(lambda: "anomaly_status" > 0)
              .message('Anomaly detected: Wind Speed: {{ index .Fields "wind_speed" }}, Grid Active Power: {{ index .Fields "grid_active_power" }}, Anomaly Status: {{ index .Fields "anomaly_status" }}')
              .mqtt('my_mqtt_broker')
              .topic('alerts/wind_turbine')
              .qos(1)
          |log()
              .level('INFO')
          |influxDBOut()
              .buffer(0)
              .database('datain')
              .measurement('opcua')
              .retentionPolicy('autogen')
      ```
       - Key sections:
         - **Input**: Fetch data from Telegraf (stream).
         - **Processing**: Apply UDFs for analytics.
         - **Alerts**: Configuration for publishing alerts (e.g., MQTT). Refer [link](./how-to-configure-alerts.md#publish-mqtt-alerts)
         - **Logging**: Set log levels (`INFO`, `DEBUG`, `WARN`, `ERROR`).
         - **Output**: Publish processed data.
      
          For more details, refer to the [Kapacitor TICK Script Documentation](https://docs.influxdata.com/kapacitor/v1/reference/tick/introduction/).

  3. **`models/`**:
     - Contains model files (e.g., `.pkl`) used by UDF python scripts.


## With Volume Mounts

> **Note**: Follow the [getting started](./get-started.md) to have the Wind Turbine Anomaly Detection sample app deployed

### Docker compose deployment Only

The files at `edge-ai-suites/manufacturing-ai-suite/industrial-edge-insights-time-series/apps/wind-turbine-anomaly-detection/time-series-analytics-config` for `Wind Turbine Anomaly Detection` sample app OR `edge-ai-suites/manufacturing-ai-suite/industrial-edge-insights-time-series/apps/weld-anomaly-detection/time-series-analytics-config` for `Weld Anomaly Detection` representing the UDF deployment package (UDFs, TICKscripts, models)
and config.json has been volume mounted for the Time Series Analytics Microservice service in `edge-ai-suites/manufacturing-ai-suite/industrial-edge-insights-time-series/docker-compose.yml`. If anything needs to be updated in the custom UDF deployment package and config.json, it has to be done at this location and the time series analytics microservice container needs to be restarted manually.

### Helm Deployment

> **Note:** This method does not use a volume mount. Instead, the `kubectl cp` command is used to copy the UDF deployment package into the container, which serves the same purpose.

1. Update the UDF deployment package by following the instructions in [Configure Time Series Analytics Microservice with Custom UDF Deployment Package](./how-to-configure-custom-udf.md#configure-time-series-analytics-microservice-with-custom-udf-deployment-package).

2. Copy the updated UDF deployment package using the [steps](./how-to-deploy-with-helm.md#copy-the-windturbine_anomaly_detection-udf-package-for-helm-deployment-to-time-series-analytics-microservice).

3. Make the following REST API call to the Time Series Analytics microservice for the updated custom UDF:
    ```sh
    curl -k -X 'POST' \
    'https://<HOST_IP>:30001/ts-api/config' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
      "udfs": {
          "name": "<custom_UDF>",
          "models": "<custom_UDF>.pkl|<custom_UDF>.cb",
          "device"": "cpu|gpu"
      },
      "alerts": {
          "mqtt": {
              "mqtt_broker_host": "ia-mqtt-broker",
              "mqtt_broker_port": 1883,
              "name": "my_mqtt_broker"
          }
      }
    }'
    ```

4. Verify the logs of the Time Series Analytics Microservice:
    ```sh
    POD_NAME=$(kubectl get pods -n ts-sample-app -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep deployment-time-series-analytics-microservice | head -n 1)
    kubectl logs -f -n ts-sample-app $POD_NAME
    ```
    
For more details, refer `Time Series Analytics` microservice API docs [here](./how-to-update-config.md#how-to-update-config-in-time-series-analytics-microservice).
