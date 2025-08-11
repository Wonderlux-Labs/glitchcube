# frozen_string_literal: true

# Test file to trigger rubocop hook - edit 2
class TestClass
  def bad_method
    puts 'This has intentional style violations'
    x = 1 + 2
    y = [1, 2, 3]
  end
end
