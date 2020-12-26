# To run these tests, simply execute `nimble test`.

import unittest
import ecolo

var x = 0

script TestSimple:
  x = 100
  yieldScript()
  x += 5
  yieldScript()
  x += 1

test "simple":
  var s = TestSimple
  s.resume()
  check x == 100
  s.resume()
  check x == 105
  s.resume()
  check x == 106
  check s == nil  # we reached the end of the script


var msg = ""

template say(str:string) =
  ## Set the current message and then suspend the script
  msg = str
  yieldScript()

proc nextmsg(s:var Script):string =
  ## Run the next part of the script and check the current message
  if s == nil:
    return ""
  s.resume()
  msg

proc nextint(s:var Script):int =
  ## Run the next part of the script and check the current number
  if s == nil:
    return -1
  s.resume()
  x
  
proc nextpart(s:var Script):Script =
  ## Run the next part of the script and return whichever function it points to next.
  if s == nil:
    return nil
  s.resume()
  s


script TestTemplates:
  say "hello"
  say "world"

test "templates":
  var s = TestTemplates
  check s.nextmsg() == "hello"
  check s.nextmsg() == "world"
  check s.nextpart() == nil


script TestIf:
  say "Hi"
  if x > 1000:
    say "Wow, that's a big number!"
  say "Bye"

test "if":
  x = 30
  var s = TestIf
  check s.nextmsg() == "Hi"
  check s.nextmsg() == "Bye"
  check s.nextpart() == nil
  
  x = 2000
  s = TestIf
  check s.nextmsg() == "Hi"
  check s.nextmsg() == "Wow, that's a big number!"
  check s.nextmsg() == "Bye"
  check s.nextpart() == nil


script TestIfElse:
  say "Welcome!"
  if x < 10: say "Not enough money."
  elif x < 20: say "Buy 1 cake?"
  else: say "How many cakes?"
  say "Goodbye!"

test "if-else":
  x = 7
  var s = TestIfElse
  check s.nextmsg() == "Welcome!"
  check s.nextmsg() == "Not enough money."
  check s.nextmsg() == "Goodbye!"
  check s.nextpart() == nil
  
  x = 12
  s = TestIfElse
  check s.nextmsg() == "Welcome!"
  check s.nextmsg() == "Buy 1 cake?"
  check s.nextmsg() == "Goodbye!"
  check s.nextpart() == nil

  x = 44
  s = TestIfElse
  check s.nextmsg() == "Welcome!"
  check s.nextmsg() == "How many cakes?"
  check s.nextmsg() == "Goodbye!"
  check s.nextpart() == nil


script TestWhile:
  x = 5
  # case x
  # of 3: yieldScript()
  # else: discard
  while x > 0:
    yieldScript()
    x -= 1

test "while":
  var s = TestWhile
  check s.nextint() == 5
  check s.nextint() == 4
  check s.nextint() == 3
  check s.nextint() == 2
  check s.nextint() == 1
  check s.nextpart() == nil


script TestLocalVar:
  var tmp = 20
  x = tmp*2
  yieldScript()
  tmp += 1
  x = tmp*2
  yieldScript()
  tmp += 2
  say "I'm " & $tmp & " years old"

test "local var":
  var s = TestLocalVar
  check s.nextint() == 40
  check s.nextint() == 42
  check s.nextmsg() == "I'm 23 years old"
  check s.nextpart() == nil


script TestLocalVarInit:
  var tmp2 = 0
  x = tmp2
  yieldScript()
  tmp2 = 100
  x = tmp2

test "local var init":
  var s = TestLocalVarInit
  check s.nextint() == 0
  check s.nextint() == 100
  s = TestLocalVarInit
  check s.nextint() == 0
  check s.nextint() == 100


script TestLocalVarInit2:
  var
    a, b = 10
    c, d: int
  x = a
  yieldScript()
  b += 2
  x = b
  yieldScript()
  x = c
  d += 1
  yieldScript()
  x = d
  yieldScript()

test "local var init 2":
  var s = TestLocalVarInit2
  check s.nextint() == 10
  check s.nextint() == 12
  check s.nextint() == 0
  check s.nextint() == 1
  s = TestLocalVarInit2
  check s.nextint() == 10
  check s.nextint() == 12
  check s.nextint() == 0
  check s.nextint() == 1

var counter: int
proc getCounter(): int =
  inc counter
  counter

script TestLet:
  let tmp3 = getCounter()
  x = tmp3
  yieldScript()
  x = tmp3 + 1

test "let":
  counter = 5
  var s = TestLet
  check s.nextint() == 6
  check s.nextint() == 7
  s = TestLet
  check s.nextint() == 7
  check s.nextint() == 8

# Not yet implemented
#[
script TestCaseStmt:
  case x
  of 10:
    x = 11
  of 20:
    x = 21
    yieldScript()
  of 30:
    x = 31
    yieldScript()
    x = 32
  else:
    x = 99
    yieldScript()
    say "crikey"
  yieldScript()

test "case stmt":
  var s = TestCaseStmt
  x = 10
  check s.nextint() == 11
  check s == nil
  
  s = TestCaseStmt
  x = 20
  check s.nextint() == 21
  check s.nextint() == 21
  check s == nil
  
  s = TestCaseStmt
  x = 30
  check s.nextint() == 31
  check s.nextint() == 32
  check s == nil
  
  s = TestCaseStmt
  x = 5
  check s.nextint() == 99
  check s.nextmsg() == "crikey"
  check s.nextpart() == nil
]#

var coins: int
var choseYes: bool

script TestReadme:
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

test "readme demo":
  var s:Script = TestReadme
  coins = 120
  s.resume()
  check msg == "Welcome, would you like to buy a potion?"
  choseYes = true
  s.resume()
  check msg == "You got a potion!"
  s.resume()
  check msg == "Thank you for your business."
  s.resume()
  check msg == "See you around!"
  check s == nil

script Empty:
  yieldScript()
