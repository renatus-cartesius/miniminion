// This is a simple example of a manifest to describe some multiple files with computed names and contents.

local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

local fileMode(mode) =
  local digits = std.stringChars(mode);
  std.foldl(function(acc, digit) acc * 8 + std.parseInt(digit), digits, 0);

{
  some_file_0: Resource(
    'file',
    {
      path: '/tmp/miniminion_file_0',
      content: 'hello from file 0\n',
      mode: fileMode('777'),
    },
  ),
}
+
{
  ['some_file_' + i]: Resource(
    'file',
    {
      path: '/tmp/miniminion_file_%d' % i,
      content: 'hello from file %d\n' % i,
      mode: fileMode('777'),
    },
    deps=['some_file_%d' % (i - 1)]
  )
  for i in std.range(1, 5)

}
