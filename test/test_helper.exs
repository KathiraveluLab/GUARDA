exclude = if System.get_env("INTEGRATION_TESTS") == "true", do: [], else: [:integration]
ExUnit.start(exclude: exclude)
