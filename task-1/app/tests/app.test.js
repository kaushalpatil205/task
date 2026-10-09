const request = require('supertest');
const app = require('../src/index');

describe('Health Check', () => {
  it('GET /health returns 200 with status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});

describe('Products API', () => {
  it('GET /products returns array', async () => {
    const res = await request(app).get('/products');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  it('GET /products/:id returns product', async () => {
    const res = await request(app).get('/products/1');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('name');
  });

  it('GET /products/:id 404 for missing id', async () => {
    const res = await request(app).get('/products/9999');
    expect(res.statusCode).toBe(404);
  });

  it('POST /products creates product', async () => {
    const res = await request(app)
      .post('/products')
      .send({ name: 'Monitor', price: 15000, stock: 5 });
    expect(res.statusCode).toBe(201);
    expect(res.body.name).toBe('Monitor');
  });

  it('POST /products 400 on missing fields', async () => {
    const res = await request(app).post('/products').send({ name: 'Broken' });
    expect(res.statusCode).toBe(400);
  });

  it('DELETE /products/:id removes product', async () => {
    const res = await request(app).delete('/products/1');
    expect(res.statusCode).toBe(200);
  });
});
