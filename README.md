# Description

This project serves as a reference implementation of the Google Cloud Package DMZs design pattern using the Maxtext LLM. 

Users running TPU VMs can significantly increase the security of their Workloads by restricting external connectivity to the public Internet. However, the TPU VM will likely need to fetch external resources required by the LLM and/or additional user mananaged libraries. TPU VMs currently only offer a restricted list of base images, with no options for custom (pre-built) images.

In the case of Maxtext, the TPU VM requires network access to a variety of public and Google managed Apt and Pip repositories in order to build the LLM. 

# Installation

Create 2 Projects:
1) An outer loop project: e.g maxtext-sample-outer
2) An inner loop project: e.g maxtext-sample-inner

Configure the gcloud cli to use the outer loop project
```
gcloud config set project maxtext-sample-outer
```

Run the project_setup.sh script.
Note: See project_setup.sh script for more positional arguments
```
./project_setup.sh maxtext-sample-outer maxtext-sample-inner
```

Follow the instructions printed by the project_setup.sh script and replace the values in the corresponding Cloud Build configurations (i.e. outer-loop-scripts/cloudbuild.yaml, dmz-scripts/cloudbuild.yaml, inner-loop-scripts/cloudbuild.yaml)

Submit the Outer Loop build and see all 3 Cloud Build Pipelines run successfully. 
Note: The Outer Loop pipeline will build submit a build for the DMZ pipeline, which will submit a build for the Inner Loop pipeline.

```
gcloud builds submit \
  --async \
  --region us-central1 \
  --config=outer-loop-scripts/cloudbuild.yaml \
  .
```

The Outer Loop pipeline will take about 20 minutes to run.
The DMZ pipeline will take about 20 minutes to run the first time, and then closer to 5 minutes on subsequent runs.
The Inner Loop pipeline will take about 10 minutes to run.
