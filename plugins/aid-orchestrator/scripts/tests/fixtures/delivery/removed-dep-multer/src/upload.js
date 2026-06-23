// upload.js — still imports multer even though it was removed from package.json
const multer = require('multer');
const express = require('express');

const upload = multer({ dest: 'uploads/' });

module.exports = { upload };
