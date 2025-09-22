# PostgreSQL Pub/Sub Database Replication with Express CRUD API

A Node.js application demonstrating PostgreSQL logical replication (pub/sub) with a read/write split architecture. This project sets up two PostgreSQL instances - one for writes (primary) and one for reads (replica) - using PostgreSQL's built-in logical replication features.

## Architecture Overview

- **Primary Database (Port 6000)**: Handles all write operations (CREATE, UPDATE, DELETE)
- **Replica Database (Port 6001)**: Handles all read operations (SELECT) via logical replication
- **Express API**: CRUD operations with automatic read/write splitting
- **PostgreSQL Logical Replication**: Real-time data synchronization between databases

## Prerequisites

- Docker and Docker Compose
- Node.js (v14 or higher)
- npm or yarn
- PostgreSQL client (psql) for database setup

## Project Structure

```
pub-sub-pg/
├── app/                          # Express application
│   ├── config/
│   │   └── database.js          # Database connection pools
│   ├── controllers/
│   │   └── userController.js   # User CRUD logic
│   ├── models/
│   │   └── userModel.js        # User data model
│   ├── routes/
│   │   └── userRoutes.js       # API routes
│   ├── server.js                # Express server
│   ├── package.json
│   ├── .env.example             # Environment variables template
│   └── .gitignore
├── database/                     # Database Docker setup
│   ├── docker-compose.yml      # PostgreSQL containers
│   ├── .env.example            # Database credentials template
│   └── Makefile
├── cluster-main-db-script.sql   # Primary database setup & publication
└── cluster-worker-db-script.sql # Replica database setup & subscription
```

## Setup Instructions

### Step 1: Create Docker Network

First, create a Docker network for the PostgreSQL containers to communicate:

```bash
docker network create pg-cluster-net
```

### Step 2: Setup Database Containers

1. Navigate to the database directory:
```bash
cd database
```

2. Create environment file from template:
```bash
cp .env.example .env
```

3. Start the PostgreSQL containers:
```bash
docker-compose up -d
```

This will start two PostgreSQL instances:
- **main-db** on port 6000 (primary/write database)
- **worker-db** on port 6001 (replica/read database)

### Step 3: Initialize Primary Database

1. Connect to the primary database:
```bash
docker exec -it main-db psql -U pg -d postgres
```

2. Run the primary database script:
```sql
-- Copy and paste the contents of cluster-main-db-script.sql
-- This creates the users table and sets up the publication
```

Or run directly from file:
```bash
docker exec -i main-db psql -U pg -d postgres < ../cluster-main-db-script.sql
```

### Step 4: Initialize Replica Database

1. First, get the primary database container's IP address:
```bash
docker inspect main-db | grep IPAddress
```

2. Update the connection string in `cluster-worker-db-script.sql` with the correct IP address (replace `172.26.0.2` with your container's IP).

3. Connect to the replica database:
```bash
docker exec -it worker-db psql -U pg -d postgres
```

4. Run the replica database script:
```sql
-- Copy and paste the contents of cluster-worker-db-script.sql
-- This creates the users table and subscribes to the primary
```

Or run directly from file (after updating the IP):
```bash
docker exec -i worker-db psql -U pg -d postgres < ../cluster-worker-db-script.sql
```

### Step 5: Setup Express Application

1. Navigate to the app directory:
```bash
cd app
```

2. Install dependencies:
```bash
npm install
```

3. Create environment file from template:
```bash
cp .env.example .env
```

4. Update `.env` file with your configuration:
```env
# Server Port
PORT=3000

# Write Database Configuration (Port 6000)
WRITE_DB_HOST=localhost
WRITE_DB_PORT=6000

# Read Database Configuration (Port 6001)
READ_DB_HOST=localhost
READ_DB_PORT=6001

# Database Credentials (same for both)
DB_NAME=postgres
DB_USER=pg
DB_PASSWORD=p@ssw0rd1234
```

5. Start the application:
```bash
npm start
```

For development with auto-reload:
```bash
npm run dev
```

## API Endpoints

### Health Check
- `GET /health` - Check database connectivity

### User CRUD Operations
- `GET /api/users` - Get all users (reads from replica)
- `GET /api/users/:id` - Get user by ID (reads from replica)
- `POST /api/users` - Create new user (writes to primary)
- `PUT /api/users/:id` - Update user (writes to primary)
- `PATCH /api/users/:id` - Partial update user (writes to primary)
- `DELETE /api/users/:id` - Delete user (writes to primary)

## Testing the Setup

### 1. Test Database Connectivity
```bash
curl http://localhost:3000/health
```

Expected response:
```json
{
  "status": "healthy",
  "message": "Both read and write databases are connected",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

### 2. Create a User (Write Operation)
```bash
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "johndoe",
    "email": "john@example.com",
    "password": "securePassword123",
    "first_name": "John",
    "last_name": "Doe"
  }'
```

### 3. Get All Users (Read Operation)
```bash
curl http://localhost:3000/api/users
```

### 4. Verify Replication

Connect to both databases and check if the data is synchronized:

```bash
# Check primary database
docker exec -it main-db psql -U pg -d postgres -c "SELECT * FROM users;"

# Check replica database
docker exec -it worker-db psql -U pg -d postgres -c "SELECT * FROM users;"
```

Both should show the same data, confirming replication is working.

## How It Works

### PostgreSQL Logical Replication

1. **Publication (Primary)**: The primary database publishes changes to the `users` table
2. **Subscription (Replica)**: The replica subscribes to these changes and applies them
3. **Real-time Sync**: All INSERT, UPDATE, and DELETE operations are replicated automatically

### Read/Write Splitting

The Express application uses two connection pools:
- **writePool**: Connects to port 6000 for all write operations
- **readPool**: Connects to port 6001 for all read operations

This ensures:
- Better performance by distributing read load
- Write operations go to the primary database
- Read operations utilize the replica database

## Troubleshooting

### Replication Not Working

1. Check publication status on primary:
```sql
SELECT * FROM pg_publication;
SELECT * FROM pg_stat_replication;
```

2. Check subscription status on replica:
```sql
SELECT * FROM pg_subscription;
SELECT * FROM pg_stat_subscription;
```

3. Check replication slots on primary:
```sql
SELECT * FROM pg_replication_slots;
```

### Connection Issues

1. Verify containers are running:
```bash
docker ps
```

2. Check container logs:
```bash
docker logs main-db
docker logs worker-db
```

3. Ensure the Docker network exists:
```bash
docker network ls | grep pg-cluster-net
```

### Reset Everything

To completely reset the setup:

```bash
# Stop and remove containers
cd database
docker-compose down

# Remove data volumes
rm -rf main-db/ worker-db/

# Recreate network
docker network rm pg-cluster-net
docker network create pg-cluster-net

# Start fresh
docker-compose up -d
```

## Security Considerations

- Change default passwords in production
- Use environment variables for sensitive data
- Implement proper authentication and authorization
- Use SSL/TLS for database connections in production
- Restrict database access to specific IPs/networks
- Regular backups and monitoring

## Additional Features

The application includes:
- Password hashing with bcrypt
- Input validation
- Error handling
- CORS support
- Automatic timestamp management
- UUID primary keys
- Database indexes for performance

## License

MIT

## Contributing

Feel free to submit issues and pull requests.