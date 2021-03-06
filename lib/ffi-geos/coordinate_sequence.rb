
module Geos

  # A CoordinateSequence is a list of coordinates in a Geometry.
  class CoordinateSequence
    class ParseError < ArgumentError
    end

    class CoordinateAccessor
      attr_accessor :parent, :dimension

      include Enumerable

      def initialize(parent, dimension)
        @parent = parent
        @dimension = dimension
      end

      def [](idx)
        parent.get_ordinate(idx, self.dimension)
      end

      def []=(idx, value)
        parent.set_ordinate(idx, self.dimension, value)
      end

      def each
        if block_given?
          parent.length.times do |n|
            yield parent.get_ordinate(n, self.dimension)
          end
          self
        else
          parent.length.times.collect { |n|
            parent.get_ordinate(n, self.dimension)
          }.to_enum
        end
      end
    end

    include Enumerable

    attr_reader :ptr, :x, :y, :z

    # :call-seq:
    #   new(ptr, auto_free = true)
    #   new(size = 0, dimensions = 0)
    #   new(options)
    #   new(points)
    #
    # The ptr version of the initializer is for internal use.
    #
    # new(points) will try to glean the size and dimensions of your
    # CoordinateSequence from an Array of points. The Array should contain
    # uniform-sized Arrays which represent the [ x, y, z ] values of your
    # coordinates.
    def initialize(*args)
      points = nil # forward declaration we can use later

      ptr, auto_free = if args.first.is_a?(FFI::Pointer)
        [ args.first, args[1] ]
      else
        size, dimensions = if args.first.is_a?(Array)
          points = if args.first.first.is_a?(Array)
            args.first
          else
            args
          end
          lengths = points.collect(&:length).uniq

          if lengths.empty?
            [ 0, 0 ]
          elsif lengths.length != 1
            raise ParseError.new("Different sized points found in Array")
          elsif !lengths.first.between?(1, 3)
            raise ParseError.new("Expected points to contain 1-3 elements")
          else
            [ points.length, points.first.length ]
          end
        elsif args.first.is_a?(Hash)
          args.first.values_at(:size, :dimensions)
        else
          if !args.length.between?(0, 2)
            raise ArgumentError.new("wrong number of arguments (#{args.length} for 0-2)")
          else
            [ args[0], args[1] ]
          end
        end

        size ||= 0
        dimensions ||= 0

        [ FFIGeos.GEOSCoordSeq_create_r(Geos.current_handle, size, dimensions), true ]
      end

      @ptr = FFI::AutoPointer.new(
        ptr,
        auto_free ? self.class.method(:release) : self.class.method(:no_release)
      )

      if !auto_free
        @ptr.autorelease = false
      end

      @x = CoordinateAccessor.new(self, 0)
      @y = CoordinateAccessor.new(self, 1)
      @z = CoordinateAccessor.new(self, 2)

      if points
        points.each_with_index do |point, idx|
          point.each_with_index do |val, dim|
            self.set_ordinate(idx, dim, val)
          end
        end
      end
    end

    def initialize_copy(source)
      @ptr = FFI::AutoPointer.new(
        FFIGeos.GEOSCoordSeq_clone_r(Geos.current_handle, source.ptr),
        self.class.method(:release)
      )
    end

    def self.no_release(ptr) #:nodoc:
    end

    def self.release(ptr) #:nodoc:
      FFIGeos.GEOSCoordSeq_destroy_r(Geos.current_handle, ptr)
    end

    # Yields coordinates as [ x, y, z ]. The z coordinate may be omitted for
    # 2-dimensional CoordinateSequences.
    def each
      if block_given?
        self.length.times do |n|
          yield self.build_coordinate(n)
        end
        self
      else
        self.length.times.collect { |n|
          self.build_coordinate(n)
        }.to_enum
      end
    end

    # Sets the x value of a coordinate. Can also be set via #x[]=.
    def set_x(idx, val)
      self.check_bounds(idx)
      FFIGeos.GEOSCoordSeq_setX_r(Geos.current_handle, self.ptr, idx, val)
    end

    # Sets the y value of a coordinate. Can also be set via #y[]=.
    def set_y(idx, val)
      self.check_bounds(idx)
      FFIGeos.GEOSCoordSeq_setY_r(Geos.current_handle, self.ptr, idx, val)
    end

    # Sets the z value of a coordinate. Can also be set via #z[]=.
    def set_z(idx, val)
      self.check_bounds(idx)
      FFIGeos.GEOSCoordSeq_setZ_r(Geos.current_handle, self.ptr, idx, val)
    end

    def set_ordinate(idx, dim, val)
      self.check_bounds(idx)
      FFIGeos.GEOSCoordSeq_setOrdinate_r(Geos.current_handle, self.ptr, idx, dim, val)
    end

    # Gets the x value of a coordinate. Can also be retrieved via #x[].
    def get_x(idx)
      self.check_bounds(idx)
      FFI::MemoryPointer.new(:double).tap { |ret|
        FFIGeos.GEOSCoordSeq_getX_r(Geos.current_handle, self.ptr, idx, ret)
      }.read_double
    end

    # Gets the y value of a coordinate. Can also be retrieved via #y[].
    def get_y(idx)
      self.check_bounds(idx)
      FFI::MemoryPointer.new(:double).tap { |ret|
        FFIGeos.GEOSCoordSeq_getY_r(Geos.current_handle, self.ptr, idx, ret)
      }.read_double
    end

    # Gets the z value of a coordinate. Can also be retrieved via #z[].
    def get_z(idx)
      self.check_bounds(idx)
      FFI::MemoryPointer.new(:double).tap { |ret|
        FFIGeos.GEOSCoordSeq_getZ_r(Geos.current_handle, self.ptr, idx, ret)
      }.read_double
    end

    def get_ordinate(idx, dim)
      self.check_bounds(idx)
      FFI::MemoryPointer.new(:double).tap { |ret|
        FFIGeos.GEOSCoordSeq_getOrdinate_r(Geos.current_handle, self.ptr, idx, dim, ret)
      }.read_double
    end

    def length
      FFI::MemoryPointer.new(:int).tap { |ret|
        FFIGeos.GEOSCoordSeq_getSize_r(Geos.current_handle, self.ptr, ret)
      }.read_int
    end
    alias :size :length

    def empty?
      self.length == 0
    end

    def dimensions
      @dimensions ||= FFI::MemoryPointer.new(:int).tap { |ret|
        FFIGeos.GEOSCoordSeq_getDimensions_r(Geos.current_handle, self.ptr, ret)
      }.read_int
    end

    def to_point
      Geos.create_point(self)
    end

    def to_linear_ring
      Geos.create_linear_ring(self)
    end

    def to_line_string
      Geos.create_line_string(self)
    end

    def to_polygon
      Geos.create_polygon(self)
    end

    def to_s
      self.entries.collect { |entry|
        entry.join(' ')
      }.join(', ')
    end

    protected

    def check_bounds(idx) #:nodoc:
      if idx < 0 || idx >= self.length
        raise RuntimeError.new("Index out of bounds")
      end
    end

    def build_coordinate(n) #:nodoc:
      [
        self.get_x(n),
        (self.dimensions >= 2 ? self.get_y(n) : nil),
        (self.dimensions >= 3 ? self.get_z(n) : nil)
      ].compact
    end
  end
end
