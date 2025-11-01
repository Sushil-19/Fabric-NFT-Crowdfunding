const express = require('express');
const path = require('path');
const cors = require('cors') ;

const app = express();
const port = 3001; // You can choose any available port, e.g., 8000, 5000. Make sure it's different from your backend (4000).

// Serve static files from the current directory (where charity-frontend.html is located)
app.use(express.static(path.join(__dirname)));
app.use(cors()); 

// Route to serve the HTML file when someone accesses the root URL
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'charity-frontend.html'));
});

// Start the server
app.listen(port, () => {
    console.log(`Frontend server listening at http://localhost:${port}`);
    console.log('Open your web browser and navigate to this address.');
});