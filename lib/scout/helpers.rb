class String
  def convert_to_utf8
    if self.respond_to?('encode') # We can convert natively using Ruby >1.9 encode()
      return self.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})
    else # We can't convert natively, do nothing.
      return self
    end
  end
end