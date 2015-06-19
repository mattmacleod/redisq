require 'digest'
require 'erb'
require 'ostruct'

class Redisq
  class LuaScript
    SCRIPTS = %i(
      push
      expire
      pop
    )

    attr_reader :name, :content, :sha

    def initialize(name, params = {})
      @name = name
      @content = render(params)
      @sha = Digest::SHA1.new.hexdigest(content)
    end

    private

    def path
      File.join(__dir__, '..', 'lua', "#{ name }.lua.erb")
    end

    def render(params)
      source = File.read(path)

      context = OpenStruct.new(params).instance_eval { binding }
      ERB.new(minify(source)).result(context)
    end

    def minify(source)
      source.gsub(/^\-\-.*$\n/, '').squeeze("\n")
    end
  end
end
