# File for misc functions

class Array
  # Add pagination to an array
  def page(num)
    yield self if num > self.size
    (num...size).step(num) { |x| yield self[(x-num)...x] }
    yield self[(size-1)/num*num...size] if size > (size-1)/num*num
  end
end
