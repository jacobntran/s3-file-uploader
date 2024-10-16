const express = require('express');
const AWS = require('aws-sdk');
const multer = require('multer');
const path = require('path');

const app = express();
const port = 5000;

// Configure AWS SDK
const s3 = new AWS.S3({
    region: 'your-region', // Replace with your AWS region
});

const S3_BUCKET = 'your-bucket-name';

// Configure Multer for file upload handling
const storage = multer.memoryStorage();
const upload = multer({ storage });

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'OK', message: 'Service is healthy' });
});

// Route to handle file uploads
app.post('/upload', upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }

    const uploadParams = {
        Bucket: S3_BUCKET,
        Key: req.file.originalname,
        Body: req.file.buffer,
    };

    s3.upload(uploadParams, (err, data) => {

        print(err)
        if (err) {
            console.error('Error uploading file:', err);
            return res.status(500).json({ error: 'Error uploading file' });
        }

        res.status(200).json({ fileUrl: data.Location });
    });
});

app.listen(port, () => {
    console.log(`Server running on http://localhost:${port}`);
});
