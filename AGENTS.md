# Repository Guidelines for Narou.rb_MOD

## Project Overview
Narou.rb_MOD is a Ruby application for downloading, managing, and converting web novels from Japanese novel sites (小説家になろう, ハーメルン, カクヨム, etc.) to e-book formats (EPUB/MOBI).

**Ruby Version**: 3.4.0+

## Project Structure & Module Organization

```
├── lib/                    # Core library sources
│   ├── command/            # CLI subcommands (each file = one command)
│   ├── web/                # Web UI server components (Sinatra-based)
│   ├── mixin/              # Reusable mixins (Locker, OutputError)
│   ├── narou/              # Core namespace modules
│   └── *.rb                # Core classes (downloader, converter, etc.)
├── spec/                   # RSpec test suite
│   ├── support/            # Shared test helpers
│   └── **/*_spec.rb        # Test files
├── webnovel/               # Site-specific YAML configurations
├── preset/                 # Conversion presets
├── template/               # ERB/HAML templates
├── bin/narou               # CLI executable
└── narou.rb                # Local development entry point
```

## Build, Test, and Development Commands

### Installation & Setup
```bash
bundle install                    # Install gem dependencies
```

### Running Tests
```bash
bundle exec rspec                           # Run full test suite
bundle exec rspec spec/downloader_spec.rb   # Run single test file
bundle exec rspec spec/downloader_spec.rb:9  # Run specific line number
bundle exec rspec -e "description text"     # Run tests matching description
bundle exec rake                           # Default task runs rspec
```

### Linting & Static Analysis
```bash
bundle exec rubocop                 # Check code style
bundle exec rubocop -A              # Auto-correct style issues
bundle exec reek                    # Code smell detection
```

### Development Server
```bash
bundle exec ruby narou.rb web       # Start local web interface
bundle exec ruby narou.rb download n9669bk   # Download a novel for testing
```

## Code Style Guidelines

### File Headers
```ruby
# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#
```

### String Literals
- Use **double quotes** for all strings (per .rubocop.yml: `EnforcedStyle: double_quotes`)
- Exception: use single quotes only when escaping is required within

### Indentation & Formatting
- **Two-space indentation** (Ruby standard)
- **Maximum line length: 140 characters**
- Add `# frozen_string_literal: true` at the top of new files

### Naming Conventions
| Element | Convention | Example |
|---------|------------|---------|
| Files | snake_case | `downloader.rb`, `novel_converter.rb` |
| Classes | CamelCase | `NovelConverter`, `SiteSetting` |
| Modules | CamelCase | `Narou::Mixin::Locker` |
| Methods | snake_case | `create_subdirectory_name` |
| Constants | SCREAMING_SNAKE_CASE | `EXIT_ERROR_CODE`, `LOCAL_SETTING_DIR_NAME` |
| Instance variables | snake_case with @ | `@options`, `@stream_io` |

### Namespacing
- Core modules use `Narou::` prefix
- Commands use `Command::` module (e.g., `Command::Download`, `Command::Update`)
- Mixins use `Narou::Mixin::` prefix

### Import/Require Pattern
```ruby
# Standard library requires first
require "fileutils"
require "optparse"

# Third-party gems
require "sinatra"
require "active_support/core_ext/object/blank"

# Relative requires (use require_relative for local files)
require_relative "helper"
require_relative "inventory"
require_relative "mixin/all"
```

### Method Definitions
- Use parentheses for methods with parameters
- Parentheses optional for parameterless methods
- Guard clauses are acceptable (but `Style/IfUnlessModifier` is disabled)

## Error Handling Patterns

### Command Error Handling
```ruby
def execute(argv)
  @opt.parse!(argv)
rescue OptionParser::InvalidOption => e
  error "不明なオプションです(#{e})"
  exit Narou::EXIT_ERROR_CODE
rescue OptionParser::MissingArgument => e
  error "オプションの引数が指定されていないか正しくありません(#{e})"
  exit Narou::EXIT_ERROR_CODE
end
```

### Exit Codes (defined in `Narou` module)
- `EXIT_SUCCESS = 0` - Successful execution
- `EXIT_INTERRUPT = 126` - User interrupted (Ctrl+C)
- `EXIT_REQUEST_REBOOT = 125` - Server needs restart
- `EXIT_ERROR_CODE = 127` - General error

### Exception Handling
- Use `raise` exclusively (not `fail` or `throw`)
- The `Style/SignalException` enforces `only_raise` style
- Empty rescue blocks are allowed for intentionally suppressing exceptions

### Mixin Pattern for Error Output
```ruby
include Narou::Mixin::OutputError

def some_method
  # ...
rescue => e
  output_error($stdout, e)
end
```

## Testing Guidelines

### Test File Organization
- Place tests in `spec/` mirroring `lib/` structure
- Name test files `*_spec.rb`
- Use `describe`/`context`/`it` blocks clearly

### Test Structure Example
```ruby
describe Downloader do
  describe ".create_subdirectory_name" do
    context "小説家になろうのタイトルが渡された場合" do
      it { expect(Downloader.create_subdirectory_name("n9669bk タイトル")).to eq "96" }
    end
  end
end
```

### Test Helpers
- `spec_helper.rb` sets up environment variables (`NAROU_ENV=test`, `CI=true`)
- Database seed data is pre-populated for consistent testing
- Use `$stdout.capture { }` for capturing output

### Best Practices
- Stub network or filesystem side effects
- Use fixtures in `spec/support/` when available
- Set `ENV["NAROU_NONINTERACTIVE"] = "1"` to prevent interactive prompts

## CLI Command Pattern

Commands inherit from `CommandBase`:
```ruby
module Command
  class Download < CommandBase
    def self.oneline_help
      "指定した小説をダウンロードします"
    end

    def initialize
      super("[<target>] [options]")
      @opt.on("-f", "--force", "強制再ダウンロード") {
        @options["force"] = true
      }
    end

    def execute(argv)
      super(argv)
      # Command logic here
    end
  end
end
```

## Commit & Pull Request Guidelines

### Commit Messages
- Use imperative mood: `Add downloader retry logic`, `Fix hameln toc parsing`
- Reference issues: `Fix #123`
- Update `ChangeLog.md` for user-facing changes

### PR Requirements
1. Run `bundle exec rspec` - all tests must pass
2. Run `bundle exec rubocop` - no style violations
3. Update documentation if changing behavior

## Security Considerations

- **Never commit secrets** to the repository
- Sanitize user input (novel titles, author names) before use in shell commands
- See CVE-2021-35514 fix for command injection prevention patterns
- Validate YAML configs in `webnovel/` before deployment

## Agent-Specific Instructions

1. **Keep edits minimal and scoped** - favor incremental fixes over large refactors
2. **Respect existing APIs** - CLI commands maintain backward compatibility
3. **Check both rubocop AND reek** before submitting changes
4. **Test affected areas** - if modifying `downloader.rb`, run `bundle exec rspec spec/downloader_spec.rb`
5. **UTF-8 encoding** is default; handle Japanese text appropriately
6. **Thread safety matters** - the codebase uses `Helper::ThreadPool` for parallel processing

## Useful File References

- Exit codes & constants: `lib/narou.rb:27-31`
- Command base class: `lib/commandbase.rb`
- Database operations: `lib/database.rb`
- Site configurations: `webnovel/*.yaml`
- Test setup: `spec/spec_helper.rb`
