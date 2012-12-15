vertexShader = """
#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
attribute float cornerAngle;

// Contains: x, y, size, rotation
attribute vec4 position;

void main() {
  float rot = cornerAngle + position[3];
  vec2 xy = position.xy + vec2(cos(rot), sin(rot));
  xy *= position.z; // size
  xy += vec2(70.0, 70.0);
  gl_Position = vec4(xy / resolution * 2.0 - vec2(1.0), .0, 1.0);
  //uvResult = vec3(textureCoordinates.xy, .0);
}
"""

fragmentShader = """
#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
uniform sampler2D diffuseMap;

void main() {
  vec2 normPoint = gl_FragCoord.xy / resolution.y;
  gl_FragColor = vec4(normPoint, .0, 1.0);
  //vec4 texel = texture2D(diffuseMap, uvResult.xy);
  //gl_FragColor = texel;
}
"""

checkError = (gl, message) ->
  error = gl.getError()
  if error
    throw new Error("GL failed in #{message}: #{error}")

sizeOfFloat = 4

# Buffer contains:
#   0  x
#   4  y
#   8  size
#  12  rotation (radians)
#  16  corner angle
# Each sprite has four of the above, where only corner differs
STRIDE = 5 * sizeOfFloat

# Corner angles
BOTTOM_LEFT = Math.PI * 2 / 8 * -3
TOP_LEFT = Math.PI * 2 / 8 * 3
TOP_RIGHT = Math.PI * 2 / 8 * 1
BOTTOM_RIGHT = Math.PI * 2 / 8 * -1

class @SpriteSystem
  constructor: (gl) ->
    @gl = gl
    @buffer = gl.createBuffer()
    r = .2
    @array = new Float32Array([
      # 0   4    8      12      16
      # x   y   size  rotation  corner
       1,   1,   51,     r,     BOTTOM_LEFT,
       1,   1,   51,     r,     BOTTOM_RIGHT,
       1,   1,   51,     r,     TOP_LEFT,
       1,   1,   51,     r,     BOTTOM_RIGHT,
       1,   1,   51,     r,     TOP_RIGHT,
       1,   1,   51,     r,     TOP_LEFT,
    ])

  setRotation: (angle) ->
    for i in [0...6]
      @array[i * 5 + 3] = angle

  setPosition: (x, y) ->
    for i in [0...6]
      @array[i * 5 + 0] = x
      @array[i * 5 + 1] = y

  # Set up for drawing
  draw: (attributes) ->
    gl = @gl

    gl.enable gl.BLEND
    gl.disable gl.DEPTH_TEST
    gl.disable gl.CULL_FACE
    gl.blendFunc gl.ONE, gl.ONE_MINUS_SRC_ALPHA

    gl.bindBuffer gl.ARRAY_BUFFER, @buffer

    gl.bufferData gl.ARRAY_BUFFER, @array, gl.DYNAMIC_DRAW

    setPointer = (attr, size, offset) ->
      gl.vertexAttribPointer attr, size, gl.FLOAT, false, STRIDE, offset

    setPointer attributes.position, 4, 0
    setPointer attributes.cornerAngle, 1, 16

    gl.drawArrays gl.TRIANGLES, 0, 6

class @Graphics

  constructor: (@parentElement) ->

    @canvas = document.createElement 'canvas'
    @gl = null
    @buffer = null
    @uniforms = {}
    @attributes = {}

  init: (onFinished) ->
    callbacks = new Callbacks(onFinished)

    @parentElement.appendChild @canvas
    @canvas.width = @parentElement.clientWidth
    @canvas.height = @parentElement.clientHeight

    gl = @gl = @canvas.getContext('experimental-webgl') || @canvas.getContext('webgl')
    if not gl
      throw type: 'NoWebGL', message: 'WebGL not supported'

    @spriteSystem = new SpriteSystem(@gl)

    @updateSize @canvas.width, @canvas.height

    program = gl.createProgram()
    vs = @createShader(vertexShader, gl.VERTEX_SHADER)
    fs = @createShader(fragmentShader, gl.FRAGMENT_SHADER)
    gl.attachShader program, vs
    gl.attachShader program, fs
    #gl.deleteShader vs
    #gl.deleteShader fs
    gl.linkProgram program
    if not gl.getProgramParameter(program, gl.LINK_STATUS)
      error = gl.getProgramInfoLog program
      throw new Error('Linking failed: ' + error)

    @uniforms.resolution = gl.getUniformLocation(program, 'resolution')

    @program = program
    gl.useProgram @program

    @attributes.position = gl.getAttribLocation(program, 'position')
    gl.enableVertexAttribArray @attributes.position
    checkError gl, 'get position'
    @attributes.cornerAngle = gl.getAttribLocation(program, 'cornerAngle')
    gl.enableVertexAttribArray @attributes.cornerAngle
    checkError gl, 'get cornerAngle'

    @uniforms.diffuseMap = gl.getUniformLocation(program, 'diffuseMap')

    @texture = gl.createTexture()
    gl.pixelStorei gl.UNPACK_FLIP_Y_WEBGL, true
    image = new Image()
    image.src = 'assets/textures/test.png'
    image.onload = callbacks.add =>
      gl.bindTexture gl.TEXTURE_2D, @texture
      gl.texImage2D gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image
      gl.texParameteri gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST
      gl.texParameteri gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST
      #gl.texParameteri gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE
      #gl.texParameteri gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR
      #gl.texParameteri gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_NEAREST
      #gl.generateMipmap gl.TEXTURE_2D

  updateSize: (width, height) ->
    @canvas.width = width;
    @canvas.height = height;
    @gl.viewport 0, 0, @canvas.width, @canvas.height

  createShader: (source, type) ->
    gl = @gl
    shader = gl.createShader(type)
    gl.shaderSource shader, source
    gl.compileShader shader
    if not gl.getShaderParameter(shader, gl.COMPILE_STATUS)
      error = gl.getShaderInfoLog(shader)
      throw new Error("compile failed: #{error}")
    return shader

  animate: ->

  render: ->
    gl = @gl
    gl.clearColor .1, 0.5, .5, 1.0
    gl.clear gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT

    gl.useProgram @program
    gl.uniform2f @uniforms.resolution, @canvas.width, @canvas.height

    @spriteSystem.draw @attributes
    checkError gl, 'spriteSystem.draw'
