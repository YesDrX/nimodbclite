# -----------------------------------------------------------------------------
# Platform Specific Configuration
# -----------------------------------------------------------------------------
when defined(windows):
  const LibName = "odbc32.dll"
  {.pragma: odbcApi, stdcall, dynlib: LibName, importc.}
else:
  # Prioritize .2 (64-bit SQLLEN) to prevent crashing on v1 (32-bit SQLLEN) systems
  const LibName = "libodbc.so.2(|libodbc.so)"
  {.pragma: odbcApi, cdecl, dynlib: LibName, importc.}

# -----------------------------------------------------------------------------
# ODBC Primitive Types
# -----------------------------------------------------------------------------
type
  SqlChar*      = char
  SqlSChar*     = int8
  SqlSmallInt*  = int16
  SqlUSmallInt* = uint16
  SqlInt*       = int32
  SqlUInt*      = uint32
  SqlReal*      = float32
  SqlDouble*    = float64
  SqlFloat*     = float64
  
  # Handles
  SqlHandle*    = pointer
  SqlHEnv*      = SqlHandle
  SqlHDbc*      = SqlHandle
  SqlHStmt*     = SqlHandle
   
  # Pointers
  SqlPointer*   = pointer

# Length/Indicator type.
when defined(cpu64):
  type
    SqlLen*  = int64
    SqlULen* = uint64
else:
  type
    SqlLen*  = int32
    SqlULen* = uint32

# -----------------------------------------------------------------------------
# ODBC Enums
# -----------------------------------------------------------------------------

type
  # Return Codes
  SqlReturn* {.size: 2.} = enum
    SQL_INVALID_HANDLE    = -2
    SQL_ERROR             = -1
    SQL_SUCCESS           = 0
    SQL_SUCCESS_WITH_INFO = 1
    SQL_STILL_EXECUTING   = 2
    SQL_NEED_DATA         = 99
    SQL_NO_DATA           = 100

  # Handle Types
  SqlHandleType* {.size: 2.} = enum
    SQL_HANDLE_ENV  = 1
    SQL_HANDLE_DBC  = 2
    SQL_HANDLE_STMT = 3

  # Driver Completion Options
  SqlDriverCompletion* {.size: 2.} = enum
    SQL_DRIVER_NOPROMPT          = 0
    SQL_DRIVER_COMPLETE          = 1
    SQL_DRIVER_PROMPT            = 2
    SQL_DRIVER_COMPLETE_REQUIRED = 3

  # Environment Attributes
  SqlEnvAttr* {.size: 4.} = enum
    SQL_ATTR_ODBC_VERSION = 200

  # ODBC Versions
  SqlOdbcVersion* {.size: 4.} = enum
    SQL_OV_ODBC3 = 3

  # C Data Types (used in SQLBindCol/SQLGetData)
  SqlCType* {.size: 2.} = enum
    SQL_C_CHAR              = 1
    SQL_C_LONG              = 4
    SQL_C_SHORT             = 5
    SQL_C_FLOAT             = 7
    SQL_C_DOUBLE            = 8
    SQL_C_TYPE_DATE         = 91
    SQL_C_TYPE_TIME         = 92
    SQL_C_TYPE_TIMESTAMP    = 93
    SQL_C_DEFAULT           = 99

  # SQL Data Types (Returned by SQLDescribeCol)
  # Renamed to SqlType... to avoid collision with SqlChar type alias
  SqlDataType* {.size: 4.} = enum
    SqlTypeUnknown   = 0
    SqlTypeChar      = 1
    SqlTypeNumeric   = 2
    SqlTypeDecimal   = 3
    SqlTypeInteger   = 4
    SqlTypeSmallInt  = 5
    SqlTypeFloat     = 6
    SqlTypeReal      = 7
    SqlTypeDouble    = 8
    SqlTypeDatetime  = 9
    SqlTypeVarchar   = 12
    SqlTypeDate      = 91
    SqlTypeTime      = 92
    SqlTypeTimestamp = 93

const
  # Null Data Indicator
  SQL_NULL_DATA*            = -1
  # Maximum Message Length for Error Reporting
  SQL_MAX_MESSAGE_LENGTH*   = 512
  # Null Terminated String marker
  SQL_NTS*                  = -3

# -----------------------------------------------------------------------------
# FFI Procedures
# -----------------------------------------------------------------------------

proc SQLAllocHandle*(
  HandleType: SqlHandleType, 
  InputHandle: SqlHandle, 
  OutputHandle: ptr SqlHandle
): SqlReturn {.odbcApi.}

proc SQLFreeHandle*(
  HandleType: SqlHandleType, 
  Handle: SqlHandle
): SqlReturn {.odbcApi.}

proc SQLSetEnvAttr*(
  EnvironmentHandle: SqlHEnv, 
  Attribute: SqlEnvAttr, 
  Value: SqlPointer, 
  StringLength: SqlInt
): SqlReturn {.odbcApi.}

proc SQLDriverConnect*(
  ConnectionHandle: SqlHDbc, 
  WindowHandle: SqlHandle, 
  InConnectionString: ptr SqlChar, 
  StringLength1: SqlSmallInt, 
  OutConnectionString: ptr SqlChar, 
  BufferLength: SqlSmallInt, 
  StringLength2Ptr: ptr SqlSmallInt, 
  DriverCompletion: SqlDriverCompletion
): SqlReturn {.odbcApi.}

proc SQLDisconnect*(
  ConnectionHandle: SqlHDbc
): SqlReturn {.odbcApi.}

proc SQLExecDirect*(
  StatementHandle: SqlHStmt, 
  StatementText: ptr SqlChar, 
  TextLength: SqlInt
): SqlReturn {.odbcApi.}

proc SQLNumResultCols*(
  StatementHandle: SqlHStmt, 
  ColumnCount: ptr SqlSmallInt
): SqlReturn {.odbcApi.}

proc SQLRowCount*(
  StatementHandle: SqlHStmt, 
  RowCount: ptr SqlLen
): SqlReturn {.odbcApi.}

proc SQLDescribeCol*(
  StatementHandle: SqlHStmt, 
  ColumnNumber: SqlUSmallInt, 
  ColumnName: ptr SqlChar, 
  BufferLength: SqlSmallInt, 
  NameLength: ptr SqlSmallInt, 
  DataType: ptr SqlSmallInt, 
  ColumnSize: ptr SqlULen, 
  DecimalDigits: ptr SqlSmallInt, 
  Nullable: ptr SqlSmallInt
): SqlReturn {.odbcApi.}

proc SQLFetch*(
  StatementHandle: SqlHStmt
): SqlReturn {.odbcApi.}

proc SQLGetData*(
  StatementHandle: SqlHStmt, 
  ColumnNumber: SqlUSmallInt, 
  TargetType: SqlCType, 
  TargetValue: SqlPointer, 
  BufferLength: SqlLen, 
  StrLen_or_Ind: ptr SqlLen
): SqlReturn {.odbcApi.}

proc SQLGetDiagRec*(
  HandleType: SqlHandleType, 
  Handle: SqlHandle, 
  RecNumber: SqlSmallInt, 
  Sqlstate: ptr SqlChar, 
  NativeError: ptr SqlInt, 
  MessageText: ptr SqlChar, 
  BufferLength: SqlSmallInt, 
  TextLength: ptr SqlSmallInt
): SqlReturn {.odbcApi.}