const express = require('express');
const morgan = require('morgan');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(morgan('combined'));

// in-memory store — swap this with a DB later
let products = [
  { id: 1, name: 'Laptop', price: 75000, stock: 10 },
  { id: 2, name: 'Keyboard', price: 2500, stock: 50 },
];

app.get('/health', (req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

app.get('/products', (req, res) => {
  res.json(products);
});

app.get('/products/:id', (req, res) => {
  const product = products.find(p => p.id === parseInt(req.params.id));
  if (!product) return res.status(404).json({ error: 'Product not found' });
  res.json(product);
});

app.post('/products', (req, res) => {
  const { name, price, stock } = req.body;
  if (!name || price === undefined || stock === undefined) {
    return res.status(400).json({ error: 'name, price, stock are required' });
  }
  const newProduct = { id: products.length + 1, name, price, stock };
  products.push(newProduct);
  res.status(201).json(newProduct);
});

app.delete('/products/:id', (req, res) => {
  const idx = products.findIndex(p => p.id === parseInt(req.params.id));
  if (idx === -1) return res.status(404).json({ error: 'Product not found' });
  products.splice(idx, 1);
  res.json({ message: 'Deleted successfully' });
});

// only start listening when running directly, not when required in tests
if (require.main === module) {
  app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
}

module.exports = app;
