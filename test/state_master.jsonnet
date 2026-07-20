local Resource(type, args={}, deps=[]) = {
  deps: deps,
  type: type,
} + args;

{
  dummy: Resource('shell', {
    command: 'echo "master state applied on $(hostname)"',
  }),
}