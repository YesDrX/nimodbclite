import ../src/nimodbclite
import strutils

# Example: List installed ODBC drivers
proc main() =
  try:
    echo "Installed ODBC Drivers:"
    echo "=" .repeat(50)
    
    let drivers = listOdbcDrivers()
    
    if drivers.len == 0:
      echo "No ODBC drivers found."
    else:
      for i, driver in drivers:
        echo "\n[", i + 1, "] ", driver.name
        if driver.attributes.len > 0:
          for attr in driver.attributes:
            echo "    ", attr.key, " = ", attr.value
        else:
          echo "    (no attributes)"
    
    echo "\n", "=" .repeat(50)
    echo "Total drivers found: ", drivers.len
    
  except OdbcException as e:
    echo "ODBC Error: ", e.msg
    echo "SQLState: ", e.sqlState
  except Exception as e:
    echo "Error: ", e.msg

main()
