# frozen_string_literal: true

module Services
  # Service for discovering, cataloging, and generating specifications for tools
  # Supports both isolated testing and LLM function calling
  class ToolRegistryService
    class ToolError < StandardError; end

    class << self
      # Initialize and eagerly load all tools on startup
      def initialize!
        puts "🔧 Loading tool registry..." if defined?(Rails) || ENV['RACK_ENV'] == 'development'
        @tools_cache = build_tool_registry
        puts "✅ Loaded #{@tools_cache.size} tools: #{@tools_cache.keys.join(', ')}" if defined?(Rails) || ENV['RACK_ENV'] == 'development'
        @tools_cache
      rescue StandardError => e
        puts "❌ Failed to load tools: #{e.message}"
        raise e
      end
      
      # Get all available tools with their metadata
      #
      # @return [Hash] Tool registry with name, description, parameters, etc.
      def discover_tools
        @tools_cache ||= build_tool_registry
      end

      # Get tool specifications formatted for OpenAI function calling
      #
      # @param tool_names [Array<String>] Specific tools to include, or all if nil
      # @param context [Symbol] Context for tool filtering (:all, :character_specific, etc.)
      # @return [Array<Hash>] OpenAI function schemas
      def get_openai_functions(tool_names = nil, context: :all)
        tools = discover_tools
        selected_tools = tool_names ? tools.select { |name, _| tool_names.include?(name) } : tools

        selected_tools.map do |name, tool_info|
          build_openai_function_schema(name, tool_info)
        end
      end

      # Get tool prompt for system prompt generation
      #
      # @param tool_name [String] Name of the tool
      # @return [String] Tool prompt or description
      def get_tool_prompt(tool_name)
        tools = discover_tools
        tool_info = tools[tool_name]
        return 'Unknown tool' unless tool_info

        tool_class = tool_info[:ruby_class]
        if tool_class.respond_to?(:tool_prompt)
          tool_class.tool_prompt
        elsif tool_class.respond_to?(:description)
          tool_class.description
        else
          'Tool capability'
        end
      end

      # Get OpenAI function schemas for method-based tools
      #
      # @param tool_names [Array<String>] Specific tools to include
      # @return [Array<Hash>] OpenAI function schemas for all methods
      def get_tool_methods_as_functions(tool_names = nil)
        tools = discover_tools
        selected_tools = tool_names ? tools.select { |name, _| tool_names.include?(name) } : tools

        functions = []
        selected_tools.each do |tool_name, tool_info|
          tool_class = tool_info[:ruby_class] || load_tool_class(tool_name)
          next unless tool_class
          
          methods = get_tool_methods(tool_class)
          methods.each do |method_name, method_info|
            functions << build_method_function_schema(tool_name, method_name, method_info)
          end
        end
        
        functions
      end

      # Build OpenAI function schema for a specific method
      def build_method_function_schema(tool_name, method_name, method_info)
        properties = {}
        required = []

        # Add required parameters
        method_info[:parameters][:required].each do |param|
          properties[param[:name]] = {
            type: param[:type],
            description: param[:description] || "#{param[:name]} parameter"
          }
          required << param[:name]
        end

        # Add optional parameters
        method_info[:parameters][:optional].each do |param|
          properties[param[:name]] = {
            type: param[:type], 
            description: param[:description] || "#{param[:name]} parameter (optional)"
          }
        end

        {
          type: 'function',
          function: {
            name: "#{tool_name}__#{method_name}", # Use double underscore to separate tool and method
            description: method_info[:description],
            parameters: {
              type: 'object',
              properties: properties,
              required: required
            }
          }
        }
      end

      # Get tool specifications for character/context aggregation
      #
      # @param character [String] Character name (buddy, jax, lomi, etc.)
      # @param context [Hash] Additional context for tool selection
      # @return [Array<Hash>] Filtered and contextualized tool list
      def get_tools_for_character(character, context = {})
        all_tools = discover_tools
        
        # Get character tools from CharacterService - this consolidates all character config
        require_relative 'character_service'
        character_tool_names = Services::CharacterService.get_character_tools(character)

        # Filter to available tools and add context
        available_character_tools = character_tool_names.select { |tool| all_tools.key?(tool) }
        
        get_openai_functions(available_character_tools, context: :character_specific)
      end

      # Execute a tool directly (for admin testing)
      #
      # @param tool_name [String] Name of tool to execute
      # @param parameters [Hash] Parameters to pass to tool
      # @return [Hash] Execution result with timing and error handling
      def execute_tool_directly(tool_name, parameters = {})
        start_time = Time.now
        
        tool_info = discover_tools[tool_name]
        return { success: false, error: "Tool not found: #{tool_name}" } unless tool_info

        begin
          # Use the stored Ruby class reference if available
          tool_class = tool_info[:ruby_class] || load_tool_class(tool_name)
          return { success: false, error: "Could not load tool class: #{tool_name}" } unless tool_class

          # Normalize parameters
          normalized_params = normalize_parameters(parameters, tool_info[:parameters])
          
          # Execute tool
          result = tool_class.call(**normalized_params)
          
          {
            success: true,
            result: result,
            tool_name: tool_name,
            parameters: normalized_params,
            execution_time_ms: ((Time.now - start_time) * 1000).round(2),
            executed_at: Time.now.iso8601
          }
        rescue ArgumentError => e
          {
            success: false,
            error: "Invalid arguments: #{e.message}",
            tool_name: tool_name,
            parameters: parameters,
            execution_time_ms: ((Time.now - start_time) * 1000).round(2)
          }
        rescue StandardError => e
          {
            success: false,
            error: "Execution error: #{e.message}",
            tool_name: tool_name,
            parameters: parameters,
            execution_time_ms: ((Time.now - start_time) * 1000).round(2),
            backtrace: e.backtrace.first(5)
          }
        end
      end

      # Clear tools cache (for development)
      def refresh_cache!
        @tools_cache = nil
        discover_tools
      end

      # Extract all public methods from tool class that can be called
      def get_tool_methods(tool_class)
        # Get all public methods except inherited ones and framework methods
        exclude_methods = [:name, :description, :category, :parameters, :required_parameters, :examples, :call, 
                          :allocate, :superclass, :subclasses, :attached_object, :new]
        tool_methods = tool_class.public_methods(false) - exclude_methods
        
        methods = {}
        tool_methods.each do |method_name|
          next if method_name.to_s.start_with?('_') # Skip private-ish methods
          next if method_name.to_s.start_with?('get_') && !method_name.to_s.match?(/(status|state|info)/) # Skip internal getters unless they're status methods
          next if method_name.to_s.start_with?('parse_') # Skip internal parse methods
          
          begin
            method = tool_class.method(method_name)
            params = extract_method_parameters(method)
            
            methods[method_name.to_s] = {
              description: generate_method_description(method_name, params),
              parameters: params
            }
          rescue StandardError => e
            # Skip methods we can't analyze
            next
          end
        end
        
        methods
      end

      # Extract parameter information from a specific method
      def extract_method_parameters(method)
        parameters = method.parameters
        
        required = []
        optional = []
        
        parameters.each do |type, name|
          case type
          when :keyreq
            required << { 
              name: name.to_s, 
              type: infer_parameter_type(name),
              required: true 
            }
          when :key
            optional << { 
              name: name.to_s, 
              type: infer_parameter_type(name),
              required: false 
            }
          when :keyrest
            # **kwargs parameter - skip for now
          end
        end

        { required: required, optional: optional }
      rescue StandardError => e
        { required: [], optional: [] }
      end

      # Infer parameter type from name
      def infer_parameter_type(param_name)
        name = param_name.to_s
        case name
        when /color/
          'string'
        when /brightness|volume|duration|transition|pulses|limit/
          'number'  
        when /verbose|rainbow|enabled/
          'boolean'
        when /rgb_color|variables/
          'array'
        else
          'string'
        end
      end

      # Generate a description for a method
      def generate_method_description(method_name, params)
        method_str = method_name.to_s.gsub('_', ' ').gsub(/\b\w/) { |match| match.upcase }
        required_params = params[:required].map { |p| p[:name] }.join(', ')
        optional_params = params[:optional].map { |p| p[:name] }.join(', ')
        
        desc = "#{method_str}"
        if required_params.any?
          desc += ". Required: #{required_params}"
        end
        if optional_params.any?
          desc += ". Optional: #{optional_params}"
        end
        desc
      end

      private

      # Build the complete tool registry by scanning lib/tools/
      def build_tool_registry
        tools = {}
        tool_files = discover_tool_files
        
        tool_files.each do |tool_file|
          begin
            tool_info = analyze_tool_file(tool_file)
            tools[tool_info[:name]] = tool_info if tool_info
          rescue StandardError => e
            Rails.logger.warn "Failed to analyze tool file #{tool_file}: #{e.message}" if defined?(Rails)
          end
        end

        tools
      end

      # Discover all tool files in lib/tools/
      def discover_tool_files
        tools_dir = if defined?(Rails)
                      Rails.root.join('lib', 'tools')
                    else
                      File.expand_path('../../tools', __FILE__)
                    end

        return [] unless Dir.exist?(tools_dir)

        Dir.glob(File.join(tools_dir, '*.rb')).sort
      end

      # Analyze a single tool file and extract metadata
      def analyze_tool_file(tool_file)
        # Skip base_tool.rb as it's an abstract class
        return nil if File.basename(tool_file) == 'base_tool.rb'
        
        # Load the tool file
        require tool_file
        
        # Extract tool name from filename
        base_name = File.basename(tool_file, '.rb')
        
        # Try to find the tool class
        tool_class = load_tool_class_from_file(base_name)
        return nil unless tool_class

        # Extract metadata from the class
        {
          name: tool_class.respond_to?(:name) ? tool_class.name : base_name,
          class_name: tool_class.to_s,  # Get the actual Ruby class name (e.g., "LightingTool")
          ruby_class: tool_class,  # Store the actual class reference for direct use
          description: tool_class.respond_to?(:description) ? tool_class.description : 'No description available',
          file_path: tool_file,
          parameters: extract_tool_parameters(tool_class),
          examples: extract_tool_examples(tool_class),
          character_specific: infer_character_specific(tool_class),
          category: infer_tool_category(tool_class, base_name)
        }
      rescue StandardError => e
        Rails.logger.warn "Failed to analyze tool #{tool_file}: #{e.message}" if defined?(Rails)
        nil
      end

      # Load tool class from filename
      def load_tool_class_from_file(base_name)
        # Try different naming conventions
        class_names = [
          base_name.split('_').map(&:capitalize).join, # test_tool -> TestTool
          "#{base_name.split('_').map(&:capitalize).join}Tool", # test -> TestTool
          base_name.split('_').map(&:capitalize).join.gsub('Tool', '') + 'Tool' # Normalize
        ].uniq

        class_names.each do |class_name|
          return Object.const_get(class_name) if Object.const_defined?(class_name)
        end

        nil
      end

      # Extract parameter information from a specific method
      def extract_method_parameters(method)
        parameters = method.parameters
        
        required = []
        optional = []
        
        parameters.each do |type, name|
          case type
          when :keyreq
            required << { 
              name: name.to_s, 
              type: infer_parameter_type(name),
              required: true 
            }
          when :key
            optional << { 
              name: name.to_s, 
              type: infer_parameter_type(name),
              required: false 
            }
          when :keyrest
            # **kwargs parameter - skip for now
          end
        end

        { required: required, optional: optional }
      rescue StandardError => e
        { required: [], optional: [] }
      end

      # Infer parameter type from name
      def infer_parameter_type(param_name)
        name = param_name.to_s
        case name
        when /color/
          'string'
        when /brightness|volume|duration|transition|pulses|limit/
          'number'  
        when /verbose|rainbow|enabled/
          'boolean'
        when /rgb_color|variables/
          'array'
        else
          'string'
        end
      end

      # Generate a description for a method
      def generate_method_description(method_name, params)
        method_str = method_name.to_s.gsub('_', ' ').gsub(/\b\w/) { |match| match.upcase }
        required_params = params[:required].map { |p| p[:name] }.join(', ')
        optional_params = params[:optional].map { |p| p[:name] }.join(', ')
        
        desc = "#{method_str}"
        if required_params.any?
          desc += ". Required: #{required_params}"
        end
        if optional_params.any?
          desc += ". Optional: #{optional_params}"
        end
        desc
      end

      # Extract parameter information from tool class (legacy method for compatibility)  
      def extract_tool_parameters(tool_class)
        # For new method-based tools, return the first method as default
        methods = get_tool_methods(tool_class)
        if methods.any?
          first_method = methods.values.first
          return first_method[:parameters] if first_method
        end
        
        # Legacy fallback
        return { required: [], optional: [] } unless tool_class.respond_to?(:call)

        method = tool_class.method(:call)
        parameters = method.parameters
        
        required = []
        optional = []
        
        parameters.each do |type, name|
          case type
          when :keyreq
            required << { name: name.to_s, type: 'string' }
          when :key
            optional << { name: name.to_s, type: 'string' }
          when :keyrest
            # **kwargs parameter - could be anything
          end
        end

        { required: required, optional: optional }
      rescue StandardError => e
        Rails.logger.warn "Failed to extract parameters for #{tool_class}: #{e.message}" if defined?(Rails)
        { required: [], optional: [] }
      end

      # Parse tool description for parameter information
      def parse_description_for_parameters(description)
        # Look for patterns like "Args: param (type) - description"
        params = {}
        
        # Match patterns like: "action (string), params (string) - JSON parameters"
        if description =~ /Args:\s*(.+?)(?:\.|$)/mi
          args_text = $1
          
          # Split by commas and parse each parameter
          args_text.split(',').each do |arg|
            # Match "param_name (type) - description" or "param_name (type)"
            if arg.match(/(\w+)\s*\(([^)]+)\)(?:\s*-\s*(.+))?/)
              param_name = $1.strip
              param_type = $2.strip.downcase
              param_description = $3&.strip
              
              # Map common type names
              openai_type = case param_type
                           when 'string', 'str' then 'string'
                           when 'integer', 'int', 'number' then 'integer'
                           when 'boolean', 'bool' then 'boolean'
                           when 'array', 'list' then 'array'
                           when 'object', 'hash', 'json' then 'object'
                           else 'string'
                           end
              
              params[param_name] = {
                type: openai_type,
                description: param_description
              }
            end
          end
        end
        
        # Enhanced parsing for complex tool descriptions
        enhanced_params = extract_enhanced_parameters(description)
        params.merge!(enhanced_params)
        
        params
      end

      # Extract enhanced parameter details from complex descriptions
      def extract_enhanced_parameters(description)
        params = {}
        
        # For tools with action-based structure, parse actions and their parameters
        if description.include?('Actions:')
          actions = extract_actions_from_description(description)
          if actions.any?
            params['action'] = {
              type: 'string',
              description: 'Action to perform',
              enum: actions.keys,
              actions_detail: actions
            }
            
            # Parse common parameter patterns
            if description.include?('params')
              params['params'] = {
                type: 'object',
                description: 'Parameters object (varies by action - see actions_detail for specifics)'
              }
            end
          end
        end
        
        # Extract enum values from descriptions
        extract_enum_parameters(description, params)
        
        params
      end

      # Extract actions and their details from tool descriptions
      def extract_actions_from_description(description)
        actions = {}
        
        # Pattern: "action" (param1, param2, param3)
        description.scan(/"([^"]+)"\s*\(([^)]*)\)/) do |action_name, action_params|
          param_details = parse_action_parameters(action_params)
          actions[action_name] = {
            description: "#{action_name} action",
            parameters: param_details
          }
        end
        
        # If no quoted actions, try without quotes
        if actions.empty?
          description.scan(/(\w+)\s*\(([^)]*)\)/) do |action_name, action_params|
            # Skip common words that aren't actions
            next if %w[Args string boolean integer].include?(action_name)
            
            param_details = parse_action_parameters(action_params)
            actions[action_name] = {
              description: "#{action_name} action",
              parameters: param_details
            }
          end
        end
        
        actions
      end

      # Parse parameters within action parentheses
      def parse_action_parameters(param_string)
        return [] if param_string.strip.empty?
        
        params = param_string.split(',').map(&:strip)
        params.map do |param|
          # Remove common type indicators
          clean_param = param.gsub(/\(.*?\)/, '').strip
          {
            name: clean_param,
            required: true,
            description: "#{clean_param} parameter for this action"
          }
        end
      end

      # Extract enum values and parameter constraints
      def extract_enum_parameters(description, params)
        # Extract target options: "Targets: cube, cart, voice_ring, matrix, indicators, all"
        if match = description.match(/Targets?:\s*([^.]+)/)
          values = match[1].split(',').map(&:strip)
          if params['params']
            params['params'][:properties] ||= {}
            params['params'][:properties][:target] = {
              type: 'string',
              description: 'Target entity or group',
              enum: values
            }
          end
        end
        
        # Extract color formats: "Colors: hex "#FF0000" or RGB [255,0,0]"
        if description.include?('Colors:')
          if params['params']
            params['params'][:properties] ||= {}
            params['params'][:properties][:color] = {
              type: 'string', 
              description: 'Color in hex format (#FF0000) or RGB array [255,0,0]',
              examples: ['#FF0000', '#00FF00', '#0000FF', '[255,0,0]', '[0,255,0]']
            }
          end
        end
        
        # Extract mood/scene options
        if match = description.match(/mood[s]?:\s*([^.]+)/i)
          values = match[1].split(',').map(&:strip)
          if params['params']
            params['params'][:properties] ||= {}
            params['params'][:properties][:mood] = {
              type: 'string',
              description: 'Mood or scene name',
              enum: values
            }
          end
        end
      end

      # Merge parsed parameter info with extracted parameters
      def merge_parameter_info(required, optional, parsed_params)
        # Update required parameters with parsed info
        required.each do |param|
          if parsed_info = parsed_params[param[:name]]
            param.merge!(parsed_info)
          end
        end
        
        # Update optional parameters with parsed info  
        optional.each do |param|
          if parsed_info = parsed_params[param[:name]]
            param.merge!(parsed_info)
          end
        end
        
        # Add any additional parameters found in description
        parsed_params.each do |name, info|
          unless required.any? { |p| p[:name] == name } || optional.any? { |p| p[:name] == name }
            optional << { name: name }.merge(info)
          end
        end
      end

      # Extract usage examples from tool class if available
      def extract_tool_examples(tool_class)
        # This could be extended to look for example methods, comments, etc.
        []
      end

      # Infer if tool is character-specific
      def infer_character_specific(tool_class)
        # Could analyze tool behavior, description, etc.
        false
      end

      # Infer tool category from class and name
      def infer_tool_category(tool_class, name)
        case name
        when /lighting/
          'environment_control'
        when /music|audio|sound/
          'media_control'  
        when /camera|display|visual/
          'visual_interface'
        when /test|debug/
          'development_tools'
        when /home_assistant/
          'system_integration'
        when /error/
          'error_handling'
        else
          'general_tools'
        end
      end

      # Build OpenAI function schema from tool info
      def build_openai_function_schema(name, tool_info)
        properties = {}
        required = []

        # Add required parameters
        tool_info[:parameters][:required].each do |param|
          properties[param[:name]] = {
            type: param[:type],
            description: param[:description] || "#{param[:name]} parameter"
          }
          required << param[:name]
        end

        # Add optional parameters
        tool_info[:parameters][:optional].each do |param|
          properties[param[:name]] = {
            type: param[:type],
            description: param[:description] || "#{param[:name]} parameter (optional)"
          }
        end

        {
          type: 'function',
          function: {
            name: name,
            description: tool_info[:description],
            parameters: {
              type: 'object',
              properties: properties,
              required: required
            }
          }
        }
      end

      # Load tool class (similar to ToolExecutor but simplified)
      def load_tool_class(tool_name)
        # First check if we already have the tool info with class name
        tool_info = discover_tools[tool_name]
        if tool_info && tool_info[:class_name]
          # Try to get the actual Ruby class name (e.g., "LightingTool" not "lighting_control")
          actual_class = tool_info[:class_name]
          return Object.const_get(actual_class) if Object.const_defined?(actual_class)
        end
        
        # Try the same logic as ToolExecutor
        class_name = "#{tool_name.split('_').map(&:capitalize).join}Tool"
        return Object.const_get(class_name) if Object.const_defined?(class_name)

        # Load tool file if needed
        load_tool_file(tool_name)
        Object.const_get(class_name) if Object.const_defined?(class_name)
      rescue NameError
        nil
      end

      # Load tool file (same as ToolExecutor)
      def load_tool_file(tool_name)
        tool_file = if defined?(Rails)
                      Rails.root.join('lib', 'tools', "#{tool_name}.rb")
                    else
                      File.expand_path("../../tools/#{tool_name}.rb", __FILE__)
                    end

        require tool_file if File.exist?(tool_file)
      rescue LoadError => e
        Rails.logger.warn "Could not load tool file for #{tool_name}: #{e.message}" if defined?(Rails)
      end

      # Normalize parameters for tool execution
      def normalize_parameters(parameters, tool_parameters)
        normalized = {}
        
        # Convert string keys to symbols
        parameters.each do |key, value|
          sym_key = key.to_s.to_sym
          normalized[sym_key] = value
        end
        
        normalized
      end
    end
  end
end