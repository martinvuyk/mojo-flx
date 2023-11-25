from .data_types import StackValue, ValueBitWidth, padding_size, ValueType
from .cache import Cache
from memory import Buffer, memcpy, memset_zero
from memory.unsafe import bitcast
from math import max

fn flx_null() -> (DTypePointer[DType.uint8], Int):
    var buffer = FlxBuffer(10)
    buffer.add_null()
    return finish_ignoring_excetion(buffer^)

fn flx(v: Int) -> (DTypePointer[DType.uint8], Int):
    var buffer = FlxBuffer(10)
    buffer.add(v)
    return finish_ignoring_excetion(buffer^)

fn flx[D: DType](v: SIMD[D, 1]) -> (DTypePointer[DType.uint8], Int):
    var buffer = FlxBuffer(10)
    buffer.add(v)
    return finish_ignoring_excetion(buffer^)

fn flx(v: String) -> (DTypePointer[DType.uint8], Int):
    var buffer = FlxBuffer()
    buffer.add(v)
    return finish_ignoring_excetion(buffer^)

fn flx_blob(v: DTypePointer[DType.uint8], length: Int) -> (DTypePointer[DType.uint8], Int):
    var buffer = FlxBuffer()
    buffer.blob(v, length)
    return finish_ignoring_excetion(buffer^)

fn flx[D: DType](v: DTypePointer[D], length: Int) -> (DTypePointer[DType.uint8], Int):
        var buffer = FlxBuffer()
    buffer.add(v, length)
    return finish_ignoring_excetion(buffer^)

struct FlxBuffer[dedup_string: Bool = True, dedup_key: Bool = True, dedup_keys_vec: Bool = True]:
    var _stack: DynamicVector[StackValue]
    var _stack_positions: DynamicVector[Int]
    var _stack_is_vector: DynamicVector[Bool]
    var _bytes: DTypePointer[DType.uint8]
    var _size: UInt64
    var _offset: UInt64
    var _finished: Bool
    var _string_cache: Cache
    var _key_cache: Cache
    var _keys_vec_cache: Cache

    @staticmethod
    fn null() -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer(10)
        flx.add_null()
        return finish_ignoring_excetion(flx^)
        
    @staticmethod
    fn of(v: Int) -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer(10)
        flx.add(v)
        return finish_ignoring_excetion(flx^)
    
    @staticmethod
    fn of[D: DType](v: SIMD[D, 1]) -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer(10)
        flx.add(v)
        return finish_ignoring_excetion(flx^)

    @staticmethod
    fn of(v: String) -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer(len(v) + 10)
        flx.add(v)
        return finish_ignoring_excetion(flx^)

    @staticmethod
    fn from_bytes(v: DTypePointer[DType.uint8], length: Int) -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer(length + 10)
        flx.blob(v, length)
        return finish_ignoring_excetion(flx^)

    @staticmethod
    fn of[D: DType](v: DTypePointer[D], length: Int) -> (DTypePointer[DType.uint8], Int):
        var flx = FlxBuffer()
        flx.add(v, length)
        return finish_ignoring_excetion(flx^)

    fn __init__(inout self, size: UInt64 = 1 << 11):
        self._size = size
        self._stack = DynamicVector[StackValue]()
        self._stack_positions = DynamicVector[Int]()
        self._stack_is_vector = DynamicVector[Bool]()
        self._bytes = DTypePointer[DType.uint8].alloc(size.to_int())
        self._offset = 0
        self._finished = False
        self._string_cache = Cache()
        self._key_cache = Cache()
        self._keys_vec_cache = Cache()

    fn __moveinit__(inout self, owned other: Self):
        self._size = other._size^
        self._stack = other._stack^
        self._stack_positions = other._stack_positions^
        self._stack_is_vector = other._stack_is_vector^
        self._bytes = other._bytes^
        self._offset = other._offset^
        self._finished = other._finished^
        self._string_cache = other._string_cache^
        self._key_cache = other._key_cache^
        self._keys_vec_cache = other._keys_vec_cache^

    fn __copyinit__(inout self, other: Self):
        self._size = other._size
        self._stack = other._stack
        self._stack_positions = other._stack_positions
        self._stack_is_vector = other._stack_is_vector
        self._bytes = DTypePointer[DType.uint8].alloc(other._size.to_int())
        memcpy(self._bytes, other._bytes, other._offset.to_int())
        self._offset = other._offset
        self._finished = other._finished
        self._string_cache = other._string_cache
        self._key_cache = other._key_cache
        self._keys_vec_cache = other._keys_vec_cache
    
    fn __del__(owned self):
        if not self._finished:
            self._bytes.free()

    fn add_null(inout self):
        self._stack.push_back(StackValue.Null)

    fn add[D: DType](inout self, value: SIMD[D, 1]):
        self._stack.push_back(StackValue.of(value))

    fn add(inout self, value: Int):
        self._stack.push_back(StackValue.of(value))

    fn add(inout self, value: String):
        let byte_length = len(value)
        let bit_width = ValueBitWidth.of(byte_length)
        let bytes = DTypePointer[DType.uint8](value._buffer.data.bitcast[UInt8]())
        @parameter
        if dedup_string:
            let cached = self._string_cache.get((bytes, byte_length), StackValue.Null)
            if cached != StackValue.Null:
                self._stack.push_back(cached)
                return
        let byte_width = self._align(bit_width)
        self._write(byte_length, byte_width)
        let offset = self._offset
        let new_offest = self._new_offset(byte_length)
        memcpy(self._bytes.offset(self._offset.to_int()), bytes, byte_length)
        self._offset = new_offest
        self._write(0)
        let stack_value = StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.String)
        self._stack.push_back(stack_value)
        @parameter
        if dedup_string:
            let c_bytes = DTypePointer[DType.uint8].alloc(byte_length)
            memcpy(c_bytes, bytes, byte_length)
            self._string_cache.put((c_bytes, byte_length), stack_value)
    
    fn blob(inout self, value: DTypePointer[DType.uint8], length: Int):
        let bit_width = ValueBitWidth.of(length)
        let byte_width = self._align(bit_width)
        self._write(length, byte_width)
        let offset = self._offset
        let new_offest = self._new_offset(length)
        memcpy(self._bytes.offset(self._offset.to_int()), value, length)
        self._offset = new_offest
        self._stack.push_back(StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.Blob))

    fn add_indirect[D: DType](inout self, value: SIMD[D, 1]):
        let value_type = ValueType.of[D]()
        if value_type == ValueType.Int or value_type == ValueType.UInt or value_type == ValueType.Float:
            let bit_width = ValueBitWidth.of(value)
            let byte_width = self._align(bit_width)
            let offset = self._offset
            self._write(StackValue.of(value), byte_width)
            self._stack.push_back(StackValue(bitcast[DType.uint8, 8](offset), bit_width, value_type + 5))
        else: 
            self._stack.push_back(StackValue.of(value))

    fn add[D: DType](inout self, value: DTypePointer[D], length: Int):
        let len_bit_width = ValueBitWidth.of(length)
        let elem_bit_width = ValueBitWidth.of(SIMD[D, 1](0))
        if len_bit_width <= elem_bit_width:
            let bit_width = len_bit_width if elem_bit_width < len_bit_width else elem_bit_width
            let byte_width = self._align(bit_width)
            self._write(length, byte_width)
            let offset = self._offset    
            let byte_length = sizeof[D]() * length
            let new_offest = self._new_offset(byte_length)
            memcpy(self._bytes.offset(self._offset.to_int()), value.bitcast[DType.uint8](), byte_length)
            self._offset = new_offest
            self._stack.push_back(StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.of[D]() + ValueType.Vector))
        else:
            self.start_vector()
            for i in range(length):
                self.add[D](value.load(i))
            try:
                self.end()
            except:
                pass
    
    fn start_vector(inout self):
        self._stack_positions.push_back(len(self._stack))
        self._stack_is_vector.push_back(True)

    fn start_map(inout self):
        self._stack_positions.push_back(len(self._stack))
        self._stack_is_vector.push_back(False)

    fn key(inout self, s: String):
        let byte_length = len(s)
        let bit_width = ValueBitWidth.of(byte_length)
        let bytes = DTypePointer[DType.uint8](s._buffer.data.bitcast[UInt8]())
        @parameter
        if dedup_key:
            let cached = self._key_cache.get((bytes, byte_length), StackValue.Null)
            if cached != StackValue.Null:
                self._stack.push_back(cached)
                return
        let offset = self._offset
        let new_offest = self._new_offset(byte_length)
        memcpy(self._bytes.offset(self._offset.to_int()), bytes, byte_length)
        self._offset = new_offest
        self._write(0)
        let stack_value = StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.Key)
        self._stack.push_back(stack_value)
        @parameter
        if dedup_key:
            let c_bytes = DTypePointer[DType.uint8].alloc(byte_length)
            memcpy(c_bytes, bytes, byte_length)
            self._key_cache.put((c_bytes, byte_length), stack_value)

    fn end(inout self) raises:
        let position = self._stack_positions.pop_back()
        let is_vector = self._stack_is_vector.pop_back()
        if is_vector:
            self._end_vector(position)
        else:
            self._sort_keys_and_end_map(position)
    
    fn finish(owned self) raises -> (DTypePointer[DType.uint8], Int):
        return self._finish()
    
    fn _finish(inout self) raises -> (DTypePointer[DType.uint8], Int):
        self._finished = True

        while len(self._stack_positions) > 0:
            self.end()

        if len(self._stack) != 1:
            raise "Stack needs to have only one element. Instead of: " + String(len(self._stack))
        
        let value = self._stack.pop_back()
        let byte_width = self._align(value.element_width(self._offset, 0))
        self._write(value, byte_width)
        self._write(value.stored_packed_type())
        self._write(byte_width.cast[DType.uint8]())
        return self._bytes, self._offset.to_int()

    fn _align(inout self, bit_width: ValueBitWidth) -> UInt64:
        let byte_width = 1 << bit_width.value.to_int()
        self._offset += padding_size(self._offset, byte_width)
        return byte_width

    fn _write(inout self, value: StackValue, byte_width: UInt64):
        self._grow_bytes_if_needed(self._offset + byte_width)
        if value.is_offset():
            let rel_offset = self._offset - value.as_uint()
            # Safety check not implemented for now as it is internal call and should be safe
            # if byte_width == 8 or rel_offset < (1 << (byte_width * 8)):
            self._write(rel_offset, byte_width)
        else:
            let new_offset = self._new_offset(byte_width)
            self._bytes.simd_store(self._offset.to_int(), value.value)
            self._offset = new_offset

    fn _write(inout self, value: UInt64, byte_width: UInt64):
        self._grow_bytes_if_needed(self._offset + byte_width)
        let new_offset = self._new_offset(byte_width)
        self._bytes.simd_store(self._offset.to_int(), bitcast[DType.uint8, 8](value))
        # We write 8 bytes but the offset is still set to byte_width
        self._offset = new_offset

    fn _write(inout self, value: UInt8):
        self._grow_bytes_if_needed(self._offset + 1)
        let new_offset = self._new_offset(1)
        self._bytes.offset(self._offset.to_int()).store(value)
        self._offset = new_offset

    fn _new_offset(inout self, byte_width: UInt64) -> UInt64:
        let new_offset = self._offset + byte_width
        let min_size = self._offset + max(byte_width, 8)
        self._grow_bytes_if_needed(min_size)
        return new_offset

    fn _grow_bytes_if_needed(inout self, min_size: UInt64):
        let prev_size = self._size
        while self._size < min_size:
            self._size <<= 1
        if prev_size < self._size:
            let prev_bytes = self._bytes
            self._bytes = DTypePointer[DType.uint8].alloc(self._size.to_int())
            memcpy(self._bytes, prev_bytes, self._offset.to_int())
            prev_bytes.free()

    fn _end_vector(inout self, position: Int) raises:
        let length = len(self._stack) - position
        let vec = self._create_vector(position, length, 1)
        self._stack.resize(position)
        self._stack.push_back(vec)

    fn _sort_keys_and_end_map(inout self, position: Int) raises:
        if (len(self._stack) - position) & 1 == 1:
            raise "The stack needs to hold key value pairs (even number of elements). Check if you combined [key] with [add] method calls properly."
        for i in range(position + 2, len(self._stack), 2):
            let key = self._stack[i]
            let value = self._stack[i + 1]
            var j = i - 2
            while j >= position and self._should_flip(self._stack[j], key):
                self._stack[j + 2] = self._stack[j]
                self._stack[j + 3] = self._stack[j + 1]
                j -= 2
            self._stack[j + 2] = key
            self._stack[j + 3] = value
        self._end_map(position)

    fn _should_flip(self, a: StackValue, b: StackValue) raises -> Bool:
        if a.type != ValueType.Key or b.type != ValueType.Key:
            raise "Stack values are not keys " + String(a.type.value) + " " + String(a.type.value)
        var index = 0
        while True:
            let c1 = self._bytes.load(a.as_uint().to_int() + index)
            let c2 = self._bytes.load(b.as_uint().to_int() + index)
            if c1 < c2:
                return False
            if c1 > c2:
                return True
            if c1 == 0 and c2 == 0:
                return False
            index += 1
    
    fn _end_map(inout self, start: Int) raises:
        let length = (len(self._stack) - start) >> 1
        var keys = StackValue.Null
        @parameter
        if dedup_key and dedup_keys_vec:
            let keys_vec = self._create_keys_vec_value(start, length)
            let cached = self._keys_vec_cache.get(keys_vec, StackValue.Null)
            if cached != StackValue.Null:
                keys = cached
                keys_vec.get[0, DTypePointer[DType.uint8]]().free()
            else:
                keys = self._create_vector(start, length, 2)
                self._keys_vec_cache.put(keys_vec, keys)
        else:
            keys = self._create_vector(start, length, 2)
        let map = self._create_vector(start + 1, length, 2, keys)
        self._stack.resize(start)
        self._stack.push_back(map)

    fn _create_keys_vec_value(self, start: Int, length: Int) -> (DTypePointer[DType.uint8], Int):
        let size = length * 8
        let result = DTypePointer[DType.uint8].alloc(size)
        var offset = 0
        memset_zero(result, size)
        for i in range(start, len(self._stack), 2):
            result.simd_store(offset, self._stack[i].value)
            offset += 8
        return (result, size)

    fn _create_vector(inout self, start: Int, length: Int, step: Int, keys: StackValue = StackValue.Null) raises -> StackValue:
        var bit_width = ValueBitWidth.of(length)
        var prefix_elements = 1
        if keys != StackValue.Null:
            prefix_elements += 2
            let keys_bit_width = keys.element_width(self._offset, 0)
            if bit_width < keys_bit_width:
                bit_width = keys_bit_width

        let vec_elem_type = self._stack[start].type
        var typed = vec_elem_type.is_typed_vector_element()
        if keys != StackValue.Null:
            typed = False
        for i in range(start, len(self._stack), step):
            let elem_bit_width = self._stack[i].element_width(self._offset, i + prefix_elements)
            if bit_width < elem_bit_width:
                bit_width = elem_bit_width
            if vec_elem_type != self._stack[i].type:
                typed = False
            if bit_width == ValueBitWidth.width64 and typed == False:
                break
        let byte_width = self._align(bit_width)
        if keys != StackValue.Null:
            self._write(keys, byte_width)
            self._write((1 << keys.width.value).to_int(), byte_width)
        self._write(length, byte_width)
        let offset = self._offset
        for i in range(start, len(self._stack), step):
            self._write(self._stack[i], byte_width)
        if not typed:
            for i in range(start, len(self._stack), step):
                self._write(self._stack[i].stored_packed_type())
            if keys != StackValue.Null:
                return StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.Map)
            return StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.Vector)
        
        return StackValue(bitcast[DType.uint8, 8](offset), bit_width, ValueType.Vector + vec_elem_type)

fn finish_ignoring_excetion(owned flx: FlxBuffer) -> (DTypePointer[DType.uint8], Int):
    try:
        return flx^.finish()
    except e:
        # should never happen
        print("Unexpected error:", e)
        return DTypePointer[DType.uint8](), -1