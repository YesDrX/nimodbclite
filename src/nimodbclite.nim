# nimodbc.nim
import nimodbclite/odbc
import json
import strutils

# -----------------------------------------------------------------------------
# Types
# -----------------------------------------------------------------------------

# Re-export Enums
export SqlDataType

type
  OdbcConnectionObj* = object
    env: SqlHEnv
    dbc: SqlHDbc
    connected: bool

  OdbcConnection* = ref OdbcConnectionObj

  OdbcException* = object of CatchableError
    sqlState*: string
    nativeError*: int

  SqlColumn* = object
    name*: string
    sqlType*: SqlDataType
    size*: int

  ResultSet* = object
    columns*: seq[SqlColumn]
    rows*: seq[seq[string]]

  OdbcDriverInfo* = object
    name*: string
    attributes*: seq[tuple[key: string, value: string]]

proc `=destroy`(conn: var OdbcConnectionObj) =
  if conn.connected:
    discard SQLDisconnect(conn.dbc)
    conn.connected = false

  if conn.dbc != nil:
    discard SQLFreeHandle(SQL_HANDLE_DBC, conn.dbc)
    conn.dbc = nil

  if conn.env != nil:
    discard SQLFreeHandle(SQL_HANDLE_ENV, conn.env)
    conn.env = nil

# -----------------------------------------------------------------------------
# Error Handling Helper
# -----------------------------------------------------------------------------
proc checkError(ret: SqlReturn, handleType: SqlHandleType, handle: SqlHandle,
    msg: string = "") =
  if ret == SQL_SUCCESS or ret == SQL_SUCCESS_WITH_INFO or ret == SQL_NO_DATA:
    return

  var
    i: SqlSmallInt = 1
    sqlState = newString(6)
    nativeError: SqlInt
    msgText = newString(SQL_MAX_MESSAGE_LENGTH)
    textLength: SqlSmallInt
    fullMsg = ""
    lastState = ""

  while SQLGetDiagRec(
    handleType,
    handle,
    i,
    cast[ptr SqlChar](sqlState.cstring),
    addr nativeError,
    cast[ptr SqlChar](msgText.cstring),
    SQL_MAX_MESSAGE_LENGTH.SqlSmallInt,
    addr textLength
  ) == SQL_SUCCESS:
    msgText.setLen(textLength)
    let stateClean = $cast[cstring](sqlState[0].addr)
    lastState = stateClean
    fullMsg.add(if fullMsg.len > 0: "\n" else: "")
    fullMsg.add("[" & stateClean & "] " & msgText)

    msgText.setLen(SQL_MAX_MESSAGE_LENGTH)
    inc(i)

  var e: ref OdbcException
  new(e)
  e.msg = if msg.len > 0: msg & ": " & fullMsg else: fullMsg
  e.sqlState = lastState
  e.nativeError = nativeError.int
  raise e

proc newOdbcConnection*(connectionString: string): OdbcConnection =
  ## Creates a new ODBC connection using the provided connection string.
  ##
  ## This proc allocates an ODBC environment handle, sets the ODBC version to 3.x,
  ## allocates a connection handle, and establishes a connection to the database.
  ##
  ## Parameters:
  ##   - connectionString: An ODBC connection string specifying the driver, server,
  ##                       database, credentials, and other options.
  ##
  ## Returns:
  ##   An OdbcConnection object that can be used to execute queries.
  ##
  ## Raises:
  ##   OdbcException if the connection cannot be established.
  ##
  ## Examples:
  ##   - Windows SQL Server:
  ##     ```nim
  ##     let db = newOdbcConnection("Driver={SQL Server 17};Server=myServer;Database=myDB;Uid=user;Pwd=pass;")
  ##     ```
  ##   - Linux PostgreSQL:
  ##     ```nim
  ##     let db = newOdbcConnection("DRIVER={PostgreSQL};SERVER=localhost;PORT=5432;DATABASE=mydb;UID=postgres;PWD=password")
  ##     ```
  ##   - SQLite:
  ##     ```nim
  ##     let db = newOdbcConnection("DRIVER={SQLite3};Database=test.db")
  ##     ```
  result = new OdbcConnectionObj
  var ret: SqlReturn

  ret = SQLAllocHandle(SQL_HANDLE_ENV, nil, addr result.env)
  if ret != SQL_SUCCESS and ret != SQL_SUCCESS_WITH_INFO:
    raise newException(OdbcException, "Failed to allocate environment handle")

  ret = SQLSetEnvAttr(result.env, SQL_ATTR_ODBC_VERSION, cast[SqlPointer](
      SQL_OV_ODBC3), 0)
  checkError(ret, SQL_HANDLE_ENV, result.env, "Failed to set ODBC version")

  ret = SQLAllocHandle(SQL_HANDLE_DBC, result.env, addr result.dbc)
  checkError(ret, SQL_HANDLE_ENV, result.env, "Failed to allocate connection handle")

  var outConnStr = newString(1024)
  var outLen: SqlSmallInt

  ret = SQLDriverConnect(
    result.dbc,
    nil,
    cast[ptr SqlChar](connectionString.cstring),
    SQL_NTS,
    cast[ptr SqlChar](outConnStr.cstring),
    1024.SqlSmallInt,
    addr outLen,
    SQL_DRIVER_NOPROMPT
  )

  checkError(ret, SQL_HANDLE_DBC, result.dbc, "Failed to connect to database")
  result.connected = true

# -----------------------------------------------------------------------------
# Helper: Statement Lifecycle
# -----------------------------------------------------------------------------

template withStmt(conn: OdbcConnection, stmtName: untyped, body: untyped) =
  var stmtName: SqlHStmt
  var retAlloc = SQLAllocHandle(SQL_HANDLE_STMT, conn.dbc, addr stmtName)
  checkError(retAlloc, SQL_HANDLE_DBC, conn.dbc, "Failed to allocate statement")

  try:
    body
  finally:
    discard SQLFreeHandle(SQL_HANDLE_STMT, stmtName)

# -----------------------------------------------------------------------------
# Execution Logic
# -----------------------------------------------------------------------------

proc exec*(conn: OdbcConnection, query: string): int64 =
  ## Executes a SQL statement that does not return a result set.
  ##
  ## This proc is intended for DDL statements (CREATE, DROP, ALTER) and DML statements
  ## (INSERT, UPDATE, DELETE) that modify data but don't return rows.
  ##
  ## Parameters:
  ##   - conn: An active OdbcConnection.
  ##   - query: The SQL statement to execute.
  ##
  ## Returns:
  ##   The number of rows affected by the statement. For DDL statements, this may be 0
  ##   or implementation-defined.
  ##
  ## Raises:
  ##   OdbcException if the execution fails.
  ##
  ## Example:
  ##   ```nim
  ##   let rowsAffected = db.exec("INSERT INTO users (name, age) VALUES ('Alice', 30)")
  ##   echo "Inserted ", rowsAffected, " row(s)"
  ##   ```
  conn.withStmt(stmt):
    let ret = SQLExecDirect(stmt, cast[ptr SqlChar](query.cstring), SQL_NTS)
    checkError(ret, SQL_HANDLE_STMT, stmt, "Execution failed")

    var rowCount: SqlLen
    let retRows = SQLRowCount(stmt, addr rowCount)
    checkError(retRows, SQL_HANDLE_STMT, stmt, "Failed to get row count")

    return rowCount.int64

proc getColumnsMetadata(stmt: SqlHStmt): seq[SqlColumn] =
  var colCount: SqlSmallInt
  discard SQLNumResultCols(stmt, addr colCount)

  for i in 1..colCount:
    var
      colName = newString(256)
      nameLen: SqlSmallInt
      dataType: SqlSmallInt
      colSize: SqlULen
      digits: SqlSmallInt
      nullable: SqlSmallInt

    discard SQLDescribeCol(
      stmt, i.SqlUSmallInt,
      cast[ptr SqlChar](colName.cstring), 255, addr nameLen,
      addr dataType, addr colSize, addr digits, addr nullable
    )
    colName.setLen(nameLen)

    result.add(SqlColumn(
      name: colName,
      sqlType: cast[SqlDataType](dataType.int32),
      size: colSize.int
    ))

proc query*(conn: OdbcConnection, query: string): ResultSet =
  ## Executes a SQL query and returns results with metadata and all data as strings.
  ##
  ## This proc retrieves both column metadata (name, SQL type, size) and all row data.
  ## All column values are returned as strings, regardless of their actual SQL type.
  ## NULL values are represented as empty strings.
  ##
  ## Parameters:
  ##   - conn: An active OdbcConnection.
  ##   - query: The SQL SELECT statement to execute.
  ##
  ## Returns:
  ##   A ResultSet containing:
  ##     - columns: Sequence of SqlColumn with name, sqlType, and size.
  ##     - rows: Sequence of sequences of strings, where each inner sequence is a row.
  ##
  ## Raises:
  ##   OdbcException if the query execution fails.
  ##
  ## Example:
  ##   ```nim
  ##   let results = db.query("SELECT id, name, age FROM users")
  ##   for col in results.columns:
  ##     echo "Column: ", col.name, " Type: ", col.sqlType
  ##   for row in results.rows:
  ##     echo row  # Each row is a seq[string]
  ##   ```
  conn.withStmt(stmt):
    let ret = SQLExecDirect(stmt, cast[ptr SqlChar](query.cstring), SQL_NTS)
    checkError(ret, SQL_HANDLE_STMT, stmt, "Query failed")

    result.columns = getColumnsMetadata(stmt)

    while SQLFetch(stmt) == SQL_SUCCESS:
      var row: seq[string] = @[]
      for i in 1..result.columns.len:
        var buffer = newString(4096)
        var ind: SqlLen

        let retGet = SQLGetData(
          stmt, i.SqlUSmallInt, SQL_C_CHAR,
          cast[ptr SqlChar](buffer.cstring),
          buffer.len.SqlLen, addr ind
        )

        if ind == SQL_NULL_DATA:
          row.add("")
        else:
          buffer.setLen(ind)
          row.add(buffer)

      result.rows.add(row)

proc queryJson*(conn: OdbcConnection, query: string): seq[JsonNode] =
  ## Executes a SQL query and returns results as a sequence of JSON objects.
  ##
  ## This proc converts each row into a JsonNode object, with column names as keys.
  ## It performs type-aware conversion:
  ##   - Integer types (SqlTypeInteger, SqlTypeSmallInt) -> JInt
  ##   - Floating point types (SqlTypeFloat, SqlTypeReal, SqlTypeDouble) -> JFloat
  ##   - Other types (varchar, date, time, etc.) -> JString
  ##   - NULL values -> JNull
  ##
  ## Parameters:
  ##   - conn: An active OdbcConnection.
  ##   - query: The SQL SELECT statement to execute.
  ##
  ## Returns:
  ##   A sequence of JsonNode objects, where each JsonNode represents a row as a
  ##   JSON object with column names as keys.
  ##
  ## Raises:
  ##   OdbcException if the query execution fails.
  ##
  ## Example:
  ##   ```nim
  ##   let jsonResults = db.queryJson("SELECT id, name, score FROM users")
  ##   for row in jsonResults:
  ##     echo row.pretty  # Pretty-print the JSON
  ##   # Output: {"id": 1, "name": "Alice", "score": 95.5}
  ##   ```
  conn.withStmt(stmt):
    let ret = SQLExecDirect(stmt, cast[ptr SqlChar](query.cstring), SQL_NTS)
    checkError(ret, SQL_HANDLE_STMT, stmt, "Query failed")

    let meta = getColumnsMetadata(stmt)
    result = @[]

    while SQLFetch(stmt) == SQL_SUCCESS:
      var rowJson = newJObject()

      for i in 0..<meta.len:
        let col = meta[i]
        let colIdx = (i + 1).SqlUSmallInt
        var ind: SqlLen

        case col.sqlType:
        of SqlTypeInteger, SqlTypeSmallInt:
          var val: SqlInt
          discard SQLGetData(stmt, colIdx, SQL_C_LONG, addr val, sizeof(
              val).SqlLen, addr ind)
          if ind == SQL_NULL_DATA: rowJson[col.name] = newJNull()
          else: rowJson[col.name] = newJInt(val)

        of SqlTypeFloat, SqlTypeReal, SqlTypeDouble:
          var val: SqlDouble
          discard SQLGetData(stmt, colIdx, SQL_C_DOUBLE, addr val, sizeof(
              val).SqlLen, addr ind)
          if ind == SQL_NULL_DATA: rowJson[col.name] = newJNull()
          else: rowJson[col.name] = newJFloat(val)

        else:
          # Varchar, Date, Time, Timestamp, Unknown
          var buffer = newString(4096)
          discard SQLGetData(stmt, colIdx, SQL_C_CHAR, cast[ptr SqlChar](
              buffer.cstring), buffer.len.SqlLen, addr ind)
          if ind == SQL_NULL_DATA: rowJson[col.name] = newJNull()
          else:
            buffer.setLen(ind)
            rowJson[col.name] = newJString(buffer)

      result.add(rowJson)

proc listOdbcDrivers*(): seq[OdbcDriverInfo] =
  ## Lists all installed ODBC drivers on the system.
  ##
  ## This proc enumerates all available ODBC drivers by using the ODBC Driver Manager.
  ## It returns information about each driver including its name and attributes 
  ## (such as file paths, setup DLL, etc.).
  ##
  ## Returns:
  ##   A sequence of OdbcDriverInfo objects, each containing:
  ##     - name: The driver name (e.g., "PostgreSQL Unicode", "SQLite3")
  ##     - attributes: A sequence of key-value tuples with driver attributes
  ##
  ## Raises:
  ##   OdbcException if the driver enumeration fails.
  ##
  ## Example:
  ##   ```nim
  ##   let drivers = listOdbcDrivers()
  ##   for driver in drivers:
  ##     echo "Driver: ", driver.name
  ##     for attr in driver.attributes:
  ##       echo "  ", attr.key, " = ", attr.value
  ##   ```
  result = @[]
  
  var env: SqlHEnv
  var ret = SQLAllocHandle(SQL_HANDLE_ENV, nil, addr env)
  if ret != SQL_SUCCESS and ret != SQL_SUCCESS_WITH_INFO:
    raise newException(OdbcException, "Failed to allocate environment handle")
  
  defer:
    discard SQLFreeHandle(SQL_HANDLE_ENV, env)
  
  ret = SQLSetEnvAttr(env, SQL_ATTR_ODBC_VERSION, cast[SqlPointer](SQL_OV_ODBC3), 0)
  checkError(ret, SQL_HANDLE_ENV, env, "Failed to set ODBC version")
  
  var
    driverDesc = newString(256)
    descLen: SqlSmallInt
    driverAttrs = newString(2048)
    attrsLen: SqlSmallInt
    direction = SQL_FETCH_FIRST.SqlUSmallInt
  
  while true:
    ret = SQLDrivers(
      env,
      direction,
      cast[ptr SqlChar](driverDesc.cstring),
      256.SqlSmallInt,
      addr descLen,
      cast[ptr SqlChar](driverAttrs.cstring),
      2048.SqlSmallInt,
      addr attrsLen
    )
    
    if ret == SQL_NO_DATA:
      break
    
    checkError(ret, SQL_HANDLE_ENV, env, "Failed to fetch driver information")
    
    # Set proper string lengths
    driverDesc.setLen(descLen)
    driverAttrs.setLen(attrsLen)
    
    # Parse attributes (null-separated key=value pairs, double-null terminated)
    var attrs: seq[tuple[key: string, value: string]] = @[]
    var i = 0
    while i < driverAttrs.len:
      var attrStr = ""
      while i < driverAttrs.len and driverAttrs[i] != '\0':
        attrStr.add(driverAttrs[i])
        inc(i)
      
      if attrStr.len > 0:
        let parts = attrStr.split('=', maxsplit = 1)
        if parts.len == 2:
          attrs.add((key: parts[0], value: parts[1]))
        else:
          attrs.add((key: attrStr, value: ""))
      
      inc(i)  # Skip the null terminator
    
    result.add(OdbcDriverInfo(name: driverDesc, attributes: attrs))
    
    # Reset buffers for next iteration
    driverDesc = newString(256)
    driverAttrs = newString(2048)
    direction = SQL_FETCH_NEXT.SqlUSmallInt

