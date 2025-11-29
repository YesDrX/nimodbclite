import ../src/nimodbclite
import json, sequtils, sugar, strutils

# Example usage (commented out so it doesn't run without a real DB)
proc main() =
  # 1. Define Connection String
  # Windows Example: "Driver={SQL Server 17};Server=myServerAddress;Database=myDataBase;Uid=myUsername;Pwd=myPassword;TrustServerCertificate=yes;Encrypt=no;"
  # Linux Example: "DRIVER={PostgreSQL};SERVER=localhost;PORT=5432;DATABASE=mydb;UID=postgres;PWD=password"
  # Linux mysql using mariadb: "DRIVER={MariaDB Unicode};SERVER=localhost;PORT=3306;DATABASE=test;UID=test;PWD=test"
  # let connStr = "DRIVER={SQLite3};Database=test.db" 
  let connStr = "DRIVER={MariaDB Unicode};SERVER=localhost;PORT=3306;DATABASE=test;UID=test;PWD=test"

  try:
    echo "Connecting to ", connStr
    let db = newOdbcConnection(connStr)
    echo "Connected!"

    # 2. Exec (Create Table)
    let createSql = "CREATE TABLE IF NOT EXISTS test (id INTEGER, name VARCHAR(50), val DOUBLE)"
    discard db.exec(createSql)
    echo "Table created."

    let deleted = db.exec("DELETE FROM test")
    echo "Rows deleted: ", deleted

    # 3. Exec (Insert)
    let inserted = db.exec("INSERT INTO test VALUES (1, 'Alice', 10.5)")
    echo "Rows inserted: ", inserted

    # 4. Query Raw (Metadata + Strings)
    let resultSet = db.query("SELECT * FROM test")
    echo "Columns: "
    for col in resultSet.columns:
      echo " - ", col.name, " (Type: ", col.sqlType, ")"
    
    echo "Raw Data:"
    for row in resultSet.rows:
      echo " ", row

    # 5. Query JSON (Typed)
    let jsonData = db.queryJson("SELECT * FROM test")
    echo "JSON Data:"
    echo jsonData.map(it => it.pretty).join("\n\n")

  except OdbcException as e:
    echo "ODBC Error: ", e.msg
    echo "SQLState: ", e.sqlState
    
  except Exception as e:
    echo "Error: ", e.msg

main()