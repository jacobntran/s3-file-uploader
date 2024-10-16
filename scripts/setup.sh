#!/bin/bash

apt update

apt install unzip

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

unzip awscliv2.zip

./aws/install

rm -rf aws awscliv2.zip

cat << EOF > /home/ubuntu/s3-file-uploader.sh
#!/bin/bash

OBJECT=\$1
S3_BUCKET=\$2

if [ ! -e \$OBJECT ]; then
    echo "File does not exist!"
    exit 1
fi

aws s3 cp \$OBJECT s3://\$S3_BUCKET
EOF