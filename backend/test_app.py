import unittest
from app import app

class BackendTestCase(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True

    def test_health_check(self):
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"healthy", response.data)

    def test_api_route_structure(self):
        response = self.app.get('/api/data')
        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Tier 2", response.data)

if __name__ == '__main__':
    unittest.main()