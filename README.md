# nimodbclite

A lightweight ODBC wrapper library for Nim, providing a simple and type-safe interface for database connectivity across multiple database systems.

## Features

- 🚀 **Simple API**: Clean, intuitive interface for database operations
- 🔗 **Cross-Database**: Works with any ODBC-compliant database (SQL Server, PostgreSQL, MySQL, SQLite, etc.)
- 📊 **Flexible Results**: Query results as raw strings or typed JSON objects
- 🛡️ **Type-Safe**: Strong typing with proper error handling
- 💾 **Automatic Resource Management**: Automatic cleanup of database connections and statements
- 📝 **Metadata Access**: Retrieve column information (name, type, size)

## Installation

Add to your `.nimble` file:

```nim
requires "nimodbclite"
```

Or install directly:

```bash
nimble install nimodbclite
```

## Prerequisites

You need to have ODBC drivers installed for the database you want to connect to:

### Linux
- **PostgreSQL**: `apt-get install unixodbc odbc-postgresql`
- **MySQL/MariaDB**: `apt-get install unixodbc odbc-mariadb`
- **SQLite**: `apt-get install unixodbc libsqliteodbc`
- **SQL Server**: `apt-get install unixodbc msodbcsql17`

### Windows
- Most ODBC drivers come pre-installed or are available from database vendors
- SQL Server: Install Microsoft ODBC Driver for SQL Server

## Quick Start

```nim
import nimodbclite
import json

# Create a connection
let db = newOdbcConnection("DRIVER={SQLite3};Database=mydb.db")

# Execute DDL/DML statements
discard db.exec("CREATE TABLE users (id INTEGER, name VARCHAR(50), score REAL)")
let rowsInserted = db.exec("INSERT INTO users VALUES (1, 'Alice', 95.5)")
echo "Inserted ", rowsInserted, " row(s)"

# Query with string results
let results = db.query("SELECT * FROM users")
for row in results.rows:
  echo row  # seq[string]

# Query with JSON results (type-aware)
let jsonResults = db.queryJson("SELECT * FROM users")
for row in jsonResults:
  echo row.pretty
  # Output: {"id": 1, "name": "Alice", "score": 95.5}
```

## API Reference

### Connection Management

#### `newOdbcConnection(connectionString: string): OdbcConnection`

Creates a new ODBC connection using the provided connection string.

**Parameters:**
- `connectionString`: An ODBC connection string specifying driver, server, database, and credentials

**Returns:** An `OdbcConnection` object for executing queries

**Raises:** `OdbcException` if connection fails

**Connection String Examples:**

```nim
# SQL Server (Windows)
let db = newOdbcConnection(
  "Driver={SQL Server 17};Server=myServer;Database=myDB;Uid=user;Pwd=pass;TrustServerCertificate=yes;"
)

# PostgreSQL (Linux)
let db = newOdbcConnection(
  "DRIVER={PostgreSQL};SERVER=localhost;PORT=5432;DATABASE=mydb;UID=postgres;PWD=password"
)

# MySQL/MariaDB (Linux)
let db = newOdbcConnection(
  "DRIVER={MariaDB Unicode};SERVER=localhost;PORT=3306;DATABASE=test;UID=root;PWD=password"
)

# SQLite
let db = newOdbcConnection("DRIVER={SQLite3};Database=mydb.db")
```

### Query Execution

#### `exec(conn: OdbcConnection, query: string): int64`

Executes a SQL statement that does not return a result set (DDL or DML).

**Parameters:**
- `conn`: An active ODBC connection
- `query`: The SQL statement to execute

**Returns:** Number of rows affected

**Raises:** `OdbcException` if execution fails

**Example:**
```nim
# Create table
discard db.exec("CREATE TABLE products (id INT, name VARCHAR(100))")

# Insert data
let inserted = db.exec("INSERT INTO products VALUES (1, 'Widget')")
echo "Inserted ", inserted, " row(s)"

# Update data
let updated = db.exec("UPDATE products SET name = 'Gadget' WHERE id = 1")
echo "Updated ", updated, " row(s)"
```

#### `query(conn: OdbcConnection, query: string): ResultSet`

Executes a SQL query and returns results with metadata. All values are returned as strings.

**Parameters:**
- `conn`: An active ODBC connection
- `query`: The SQL SELECT statement

**Returns:** A `ResultSet` object containing:
  - `columns`: Sequence of `SqlColumn` (name, sqlType, size)
  - `rows`: Sequence of sequences of strings

**Raises:** `OdbcException` if query fails

**Example:**
```nim
let results = db.query("SELECT id, name, price FROM products")

# Access column metadata
for col in results.columns:
  echo "Column: ", col.name, " Type: ", col.sqlType, " Size: ", col.size

# Access row data (all as strings)
for row in results.rows:
  echo "ID: ", row[0], ", Name: ", row[1], ", Price: ", row[2]
```

#### `queryJson(conn: OdbcConnection, query: string): seq[JsonNode]`

Executes a SQL query and returns results as JSON objects with type-aware conversion.

**Parameters:**
- `conn`: An active ODBC connection
- `query`: The SQL SELECT statement

**Returns:** Sequence of `JsonNode` objects (one per row)

**Type Conversion:**
- Integer types → `JInt`
- Floating point types → `JFloat`
- Other types (varchar, date, time, etc.) → `JString`
- NULL values → `JNull`

**Raises:** `OdbcException` if query fails

**Example:**
```nim
let jsonResults = db.queryJson("SELECT id, name, price FROM products")

for row in jsonResults:
  # Access fields by name
  echo "Product: ", row["name"].getStr()
  echo "Price: $", row["price"].getFloat()
  
  # Pretty print JSON
  echo row.pretty()
```

## Error Handling

All database errors are raised as `OdbcException`, which includes:

```nim
type OdbcException* = object of CatchableError
  sqlState*: string       # SQL state code
  nativeError*: int       # Database-specific error code
```

**Example:**
```nim
try:
  let db = newOdbcConnection("DRIVER={SQLite3};Database=mydb.db")
  let results = db.query("SELECT * FROM nonexistent_table")
except OdbcException as e:
  echo "Database error: ", e.msg
  echo "SQL State: ", e.sqlState
  echo "Native Error: ", e.nativeError
except Exception as e:
  echo "General error: ", e.msg
```

## Data Types

### `SqlColumn`
```nim
type SqlColumn* = object
  name*: string          # Column name
  sqlType*: SqlDataType  # SQL data type
  size*: int             # Column size
```

### `ResultSet`
```nim
type ResultSet* = object
  columns*: seq[SqlColumn]    # Column metadata
  rows*: seq[seq[string]]     # Row data (all as strings)
```

### `SqlDataType` (Enum)

Available SQL types (re-exported from the underlying ODBC bindings):
- `SqlTypeChar`, `SqlTypeVarChar`
- `SqlTypeInteger`, `SqlTypeSmallInt`, `SqlTypeBigInt`
- `SqlTypeFloat`, `SqlTypeReal`, `SqlTypeDouble`
- `SqlTypeDate`, `SqlTypeTime`, `SqlTypeTimestamp`
- And more...

## Examples

### Complete Example

```nim
import nimodbclite
import json, strutils

proc main() =
  try:
    # Connect to database
    let db = newOdbcConnection("DRIVER={SQLite3};Database=example.db")
    
    # Create table
    discard db.exec("""
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY,
        name VARCHAR(100),
        department VARCHAR(50),
        salary REAL
      )
    """)
    
    # Clear existing data
    discard db.exec("DELETE FROM employees")
    
    # Insert sample data
    discard db.exec("INSERT INTO employees VALUES (1, 'Alice', 'Engineering', 85000.00)")
    discard db.exec("INSERT INTO employees VALUES (2, 'Bob', 'Sales', 65000.00)")
    discard db.exec("INSERT INTO employees VALUES (3, 'Charlie', 'Engineering', 95000.00)")
    
    # Query as strings
    echo "--- Query Results (String) ---"
    let results = db.query("SELECT name, department, salary FROM employees WHERE salary > 70000")
    for row in results.rows:
      echo row.join(" | ")
    
    # Query as JSON
    echo "\n--- Query Results (JSON) ---"
    let jsonResults = db.queryJson("SELECT * FROM employees ORDER BY salary DESC")
    for row in jsonResults:
      let name = row["name"].getStr()
      let dept = row["department"].getStr()
      let salary = row["salary"].getFloat()
      echo name, " (", dept, "): $", salary
    
  except OdbcException as e:
    echo "Database error: ", e.msg
    echo "SQL State: ", e.sqlState

main()
```

### Transaction Example

```nim
import nimodbclite

proc transferFunds(db: OdbcConnection, fromAccount: int, toAccount: int, amount: float) =
  try:
    # Start transaction
    discard db.exec("BEGIN TRANSACTION")
    
    # Debit from account
    discard db.exec("UPDATE accounts SET balance = balance - " & $amount & 
                    " WHERE id = " & $fromAccount)
    
    # Credit to account
    discard db.exec("UPDATE accounts SET balance = balance + " & $amount & 
                    " WHERE id = " & $toAccount)
    
    # Commit
    discard db.exec("COMMIT")
    echo "Transfer successful"
    
  except OdbcException as e:
    # Rollback on error
    discard db.exec("ROLLBACK")
    echo "Transfer failed: ", e.msg
```

## Resource Management

Connections are automatically cleaned up when they go out of scope, thanks to Nim's destructor system. However, you can also manually close resources if needed:

```nim
block:
  let db = newOdbcConnection("...")
  # Use database
  # Connection is automatically closed when exiting the block
```

## License

[Your license here]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## See Also

- [ODBC Documentation](https://docs.microsoft.com/en-us/sql/odbc/)
- [Nim Language](https://nim-lang.org/)
