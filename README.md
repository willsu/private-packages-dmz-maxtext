# Description

This project serves as a reference implementation of the Google Cloud Package DMZs design pattern using the Maxtext LLM. 

Users processing sensitive data with TPU VMs can significantly increase the security of their Workloads by running their workloads on a private network (VPC), preventing external connectivity to the public Internet. Preventing access to the public Internet signifanctly reduces the attack surface for potential data exfiltration and further minimizes the potential entry points for malicious actors to exploit. However, the TPU VM must still be able to install the required software (e.g. an LLM) and dependencies (Apt/Pip packages) when it is provisioned within the private network. This presents a challenge when the required software depends on a large variety of open source, externally hosted software libraries. Since we can only depended on connectivity to private software package repositories then we need a way of pre-installing the packages before the TPU VM is provisioned.

The Packages DMZ design pattern solves this problems by automating package installation through an external (unsafe) and internal (safe) GCP resource configuration. The external loop deploys a TPU VM and runs through a full installation process of Maxtext. New Apt and Pip packages/versions are detected and serialized to a list used by the DMZ build pipeline to determine which packages to sync from ther outer to inner private package repositories. The outer loop uses open source vulnerability scanning software to serialize a list of vulnerable packages that the DMZ build pipeline can use to block unsafe packages. The DMZ build pipeline syncs all non-vulnerable packages from the outer loop to the inner loop private package repositories. The inner loop build pipeline creates a TPU VM in a VPC with no external egress to the public Internet, configures the VM to pull Apt and Pip packages from their private package repositories, and runs a full installation of Maxtext on the TPU VM. The TPU VM is then considered ready to start processing data.

# Installation

Create 2 Projects:
1) An outer loop project: e.g maxtext-sample-outer
2) An inner loop project: e.g maxtext-sample-inner

Configure the gcloud cli to use the outer loop project
```
gcloud config set project maxtext-sample-outer
```

Initialize and Apply the Terraform configuration
```
terraform init

terraform apply \
  -var="outer_project_id=maxtext-qa-outer" \
  -var="outer_project_number=690154213242" \
  -var="inner_project_id=maxtext-qa-inner"
```

Follow the instructions printed by the 'terraform apply' command and replace the values in the corresponding Cloud Build configurations (i.e. outer-loop-scripts/cloudbuild.yaml, dmz-scripts/cloudbuild.yaml, inner-loop-scripts/cloudbuild.yaml)

Submit the Outer Loop build and see all 3 Cloud Build Pipelines run successfully. 
Note: The Outer Loop pipeline will build submit a build for the DMZ pipeline, which will submit a build for the Inner Loop pipeline.

```
gcloud builds submit \
  --async \
  --region us-central1 \
  --config=outer-loop-scripts/cloudbuild.yaml \
  .
```

If all is successful, there will be 2 builds that run in the outer loop and 1 build that runs in the inner loop. If the inner loop is successful, this means that the package syncing worked correctly. 

Please note: The inner loop builds with leave a TPU VM machine running, because it is expected that this machine will be used to process real data. If this is not your desired use case, please delete the TPU VM and/or an additional build step in the inner-loop-scripts/cloudbuild.yaml to delete the TPU VM.

Expected Elapsed Times for Builds:
* The Outer Loop pipeline will take about 20 minutes to run.
* The DMZ pipeline will take about 20 minutes to run the first time, and then closer to 5 minutes on subsequent runs.
* The Inner Loop pipeline will take about 10 minutes to run.
