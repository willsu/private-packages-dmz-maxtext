# ====NOTE: Taken from 'organize-packages-distributions-on-tpu'. 
# Parts of this could be used to reduce pip package download time 

# Generate a full list of pip dependencies (in requirements.txt format) based from the downloaded .whl files
echo "" > ./pip-new-packages.out
find . -name "*.whl" -maxdepth 1 \
| while IFS="" read -r PIP_WHL
  do
    # removes the leading "./" from the find output
    SHORT_PIP_WHL=$(echo $PIP_WHL | sed "s/.\///g")
    if ! grep -q $SHORT_PIP_WHL ../pip-already-stored-in-ar.out; then
      PIP_PKG=$(echo $PIP_WHL | sed -E "s/^.\/([^-]*)-([^-]*).*-.*/\1==\2/g")
      echo $PIP_PKG >> ../pip-new-packages.out
      pip download $PIP_PKG
    else
      # Remove the .whl file if the package already exists in Artifact Registry
      # This will ensure that we don't encounter 400 series errors when the .whl files are uploaded.
      rm $PIP_WHL
    fi
  done



# ====NOTE: The following code was used to replace values in the inner-setup.sh script 
# when it was being used as a startup script. The plan moving forwad is to run the startup script
# from the inner-loop-scripts cloud build pipeline, so this may be irrelevant:

# Generate a static startup script from the setup-inner.sh file.
# Replace the arguments with the required values to register the startup script for the TPU.
APT_REPO_BASE_URL="https://${REGION}-apt.pkg.dev/projects/${INNER_PROJECT_ID}"
PIP_REPO_BASE_URL="https://${REGION}-python.pkg.dev/${INNER_PROJECT_ID}"
MAXTEXT_SRC_URL=${MAXTEXT_BUCKET_URL}/maxtext-latest.tar.gz

cp inner-loop-scripts/setup-inner.sh inner-loop-scripts/setup-inner-rendered.sh
# Transform all the '/' characters to '\/' to encode for sed.
# TODO: replace sed with a more straight-forward tr command.
sed -i "s/\$\{1\}/$(echo ${APT_REPO_BASE_URL} | sed "s/\//\\\\\//g")/g" inner-loop-scripts/setup-inner-rendered.sh
sed -i "s/\$2/${APT_INNER_LOOP}/g" inner-loop-scripts/setup-inner-rendered.sh
sed -i "s/\$3/$(echo ${PIP_REPO_BASE_URL} | sed "s/\//\\\\\//g")/g" inner-loop-scripts/setup-inner-rendered.sh
sed -i "s/\$4/${PIP_INNER_LOOP}/g" inner-loop-scripts/setup-inner-rendered.sh
sed -i "s/\$5/$(echo ${MAXTEXT_SRC_URL} | sed "s/\//\\\\\//g")/g" inner-loop-scripts/setup-inner-rendered.sh


cat << EOF
After your DMZ build has run and your apt and pip packages have been successfully synced to the inner loop Artifact Repositories, you may launch a TPU VM as follows:

gcloud alpha compute tpus tpu-vm create tpu-inner \
  --zone=${REGION}-a \
  --accelerator-type=${TPU_ACCELERATOR_TYPE} \
  --version=${TPU_RUNTIME_VERSION} \
  --network=vpc-inner-loop \
  --subnetwork=subnet-inner-loop \
  --shielded-secure-boot \
  --spot \
  --internal-ips \
  --project=${INNER_PROJECT_ID} \
  --metadata='google-logging-enabled=true' \
  --metadata-from-file='startup-script=inner-loop-scripts/setup-inner-rendered.sh'

EOF