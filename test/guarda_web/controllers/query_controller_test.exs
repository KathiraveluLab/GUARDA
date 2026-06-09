defmodule GuardaWeb.QueryControllerTest do
  use ExUnit.Case, async: true

  alias GuardaWeb.QueryController

  describe "safe_query?/1" do
    test "allows simple SELECT queries" do
      assert QueryController.safe_query?("SELECT * FROM users")
      assert QueryController.safe_query?("SELECT id, name FROM products WHERE active = true")
      assert QueryController.safe_query?("select count(*) from orders")
    end

    test "allows WITH (CTE) queries" do
      assert QueryController.safe_query?("WITH cte AS (SELECT 1) SELECT * FROM cte")
    end

    test "rejects INSERT queries" do
      refute QueryController.safe_query?("INSERT INTO users (name) VALUES ('evil')")
    end

    test "rejects UPDATE queries" do
      refute QueryController.safe_query?("UPDATE users SET admin = true")
    end

    test "rejects DELETE queries" do
      refute QueryController.safe_query?("DELETE FROM users WHERE 1=1")
    end

    test "rejects DROP queries" do
      refute QueryController.safe_query?("DROP TABLE users")
      refute QueryController.safe_query?("DROP DATABASE production")
    end

    test "rejects ALTER queries" do
      refute QueryController.safe_query?("ALTER TABLE users ADD COLUMN admin boolean")
    end

    test "rejects TRUNCATE queries" do
      refute QueryController.safe_query?("TRUNCATE TABLE users")
    end

    test "rejects queries starting with non-SELECT" do
      refute QueryController.safe_query?("GRANT ALL ON users TO evil_user")
      refute QueryController.safe_query?("REVOKE ALL ON users FROM user")
    end

    test "rejects disguised destructive queries" do
      # Even if it starts with SELECT, embedded DDL/DML should be caught
      refute QueryController.safe_query?("SELECT * FROM users; DROP TABLE users")
    end
  end
end
