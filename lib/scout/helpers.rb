class Hash
  def convert_to_utf8
    result_hash = {}
    self.each do |k,v|
      new_key = k.respond_to?(:convert_to_utf8) ? k.convert_to_utf8 : k
      new_value = v.respond_to?(:convert_to_utf8) ? v.convert_to_utf8 : v
      result_hash[new_key] = new_value
    end
    return result_hash
  end
end

class String
  def convert_to_utf8
    if self.respond_to?('encode') # We can convert natively using Ruby >1.9 encode()
      return self.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})
    else # We can't convert natively, do nothing.
      return self
    end
  end
end