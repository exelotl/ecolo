ecolo
-----

A small Nim library which splits a top-level code block into several resumable parts.

This is useful for things like scripting dialog and cutscenes.

### Example

```nim
var msg: string
var coins: int
var choseYes: bool

# Defining a script:

script PotionShop:
  
  msg = "Welcome, would you like to buy a potion?"
  yieldScript()
  
  if choseYes:
    if coins < 50:
      msg = "You don't have enough money."
      yieldScript()
    else:
      coins -= 50
      msg = "You got a potion!"
      yieldScript()
      msg = "Thank you for your business."
      yieldScript()
  else:
    msg = "Oh, okay."
    yieldScript()
  
  msg = "See you around!"
  

# Executing the script:

var s:Script = PotionShop
# `s` initially is a pointer to the first function.
# We can repeatedly call s.resume() to execute it and point it to the next function.

coins = 120

s.resume()
echo msg    # "Welcome, would you like to buy a potion?"

choseYes = true
s.resume()
echo msg    # "You got a potion!"

s.resume()
echo msg    # "Thank you for your business."

s.resume()
echo msg    # "See you around!"

doAssert s == nil  # We should have now reached the end of the script
```

### Details and limitations

The `script` macro is more limited than async/await or true coroutines, but there are no closures or dynamic memory allocation involved. Code is transformed into simple top-level procedures. This means ecolo can be used for embedded development, GBA/NDS homebrew, etc.

It works like this:

Whenever a call to `yieldScript()` is encountered, the remaining code is moved to a new procedure, and a pointer to that procedure is returned.

`yieldScript()` can also work inside the following constructs:
- if / elif / else
- while (but no break or continue)

That doesn't mean you're forbidden from using `for` loops or calling other functions. It just means that you can't yield from within them.

You can use templates to hide the calls to `yieldScript()`, allowing you to define a nicer API for your use case. For example:

```nim
template say(str:string) =
  msg = str
  yieldScript()

script Foo:
  say "Hello!"
  say "How's it going?"
```
