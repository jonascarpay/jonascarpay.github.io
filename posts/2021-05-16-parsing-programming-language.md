---
title: Parsing a programming language
date: 2021-05-16
abstract:
  I recently rewrote the parser for my programming language -- twice.
  Here are some of the things I learned along the way.
tags:
  parse parsing parsec megaparsec happy alex language haskell
---

Choosing a parsing library in Haskell can be tough.
I recently rewrote the parser for my programming language's fairly complicated grammar, first from [`megaparsec`](https://hackage.haskell.org/package/megaparsec) to [`happy`](https://hackage.haskell.org/package/happy), and then from `happy` to a custom solution.
So, I had the pleasure of reimplementing the same grammar in three times, in three very different systems.
Here are some of the things I learned from that experience.

This post is not about how you write your first parser, but rather about what things to consider when writing a more complicated parser.

## Parser combinators vs. parser generators

The first choice you have to make is between parser _combinators_ and parser _generators_.

A parser _combinator_ library is the most common way of parsing in Haskell.
The idea is that the library gives you parsers to consume small pieces of input, and ways of combining those smaller parsers into larger parsers.
There are many examples of these in the Haskell ecosystem, most notably `parsec` and its progeny.

A parser _generator_ is a program that takes a formal definition of your language written in some DSL, and generates parsing code.
This is the "traditional" way of writing programming language parsers, and how most compilers work.
If you're writing Haskell, you really have only one choice here, [`happy`](https://www.haskell.org/happy/).
`happy` is well documented and used by large compilers, including [GHC](https://github.com/ghc/ghc/blob/master/compiler/GHC/Parser.y) and [PureScript](https://github.com/purescript/purescript/blob/master/lib/purescript-cst/src/Language/PureScript/CST/Parser.y).
For the rest of this post, when I talk about parser generators, you can assume I'm talking about `happy` and vice-versa.

### Static analysis

Conceptually, the main advantage of generators is the fact that they perform static analysis of your grammar.
Writing a parser is tricky, and having something check whether your grammar actually makes sense can save you many headaches.
A lot of parsing theory focuses on cases where generators can handle certain recursive grammars that are tricky to correctly implement using combinators.
In practice, however, even without recursion it's just easy write incorrect and hard-to-debug parsers using combinators, which generators would rightly reject at compile time.

Unfortunately, while the parser generator will typically give you a good description of ambiguities/conflicts, it can still be tricky to actually diagnose and fix your grammar.
This is exacerbated by the fact that what is and is not a conflict can depend on the algorithm that the generator uses.
The default $LALR(1)$ algorithm in `happy` can be quite restrictive, in ways that may be non-obvious if you don't know how the algorithm works.
Frustratingly, `happy` itself supports more flexible algorithms, but the `cabal` tooling does not allow you to configure it to use those algorithms.

More generally, there is a discussion is similar to static vs. dynamic typing.
Just like there are valid programs that can be hard to type check, you can have a perfectly fine grammar that is hard to generate a parser for.
How strongly you value that static analysis, and whether you are prepared to make concessions to your language for the sake of provable correctness is a choice you have to make per project.

A note about (left-)recursive grammars;
it is true that this can be hard to get right using parser combinators, but many parser combinator libraries provide tools to help you out with this, and I've never actually had any issues with it.
I recommend taking a look at [`makeExprParser` from `parser-combinators`](https://hackage.haskell.org/package/parser-combinators-1.3.0/docs/Control-Monad-Combinators-Expr.html#v:makeExprParser).

### Integration

The fact that parser combinators are ordinary Haskell libraries makes them really easy to integrate into your project.
On the other hand, a parser _generator_ stack with all of its glue code can require you to have duplicate definitions in several places, which means they require many times more lines of code parser combinators.

While annoying, I personally don't think this is a huge problem in practice.
The tools tend to do a good job of warning you about missing/wrong/dead code, so the actual burden of maintenance is not drastically higher.

Actually integrating `happy` into a Haskell project is also mostly painless.
Add `build-tool-depends: happy:happy` to your cabal file, and then you can use `happy`'s `.y` files as if they were ordinary `.hs` files.

### Error handling

You may have noticed before that GHC has really poor parse errors; or to be more precise, that it doesn't.
This is not GHC's fault, or `happy`'s, for that matter, this is largely [a fundamental issue with $LALR(1)$ parsers](https://stackoverflow.com/questions/5430700/how-to-get-nice-syntax-error-messages-with-happy#comment6150583_5430700).

On the other hand, at their best parser combinator libraries can give you amazing parse errors basically for free.
Consider this example from [Mark Karpov's post on the evolution of `megaparsec` error messages](https://markkarpov.com/post/evolution-of-error-messages.html):
```
1:10:
  |
1 | foo = (x $ y) * 5 + 7.2 * z
  |          ^
unexpected '$'
expecting ')', operator, or the rest of expression
```

While impressive, actually getting this quality of error messages can be tricky.
When backtracking it's easy to accidentally discard useful error messages for unclear/wrong ones, or report them at the wrong place, at which point it might be better to have no error messages at all.
The lesson here is that in theory, parser combinators are the clear winner here, but it still requires some care to actually get good error messages.

## Lexical analysis/tokenization

Lexical analysis/tokenization is the process of turning a sequence of characters into a sequence of _tokens_.
Parser generators typically expect tokenized input.
Parser combinators, on the other hand, can operate equally well on tokenized and raw input.
So, if you're using `happy`, you're going to _have_ to do tokenization, but if you're using combinators, this is the second choice you have to make.

Let's start by looking at some reasons you might _not_ want to do tokenization.

### The case against tokenization

The simple reason for not tokenizing is that adding an extra pass means extra overhead, both in terms of lines of code and performance.
In terms of code, at the very least you end up defining an extra data type to represent your tokens, plus the parser logic to operate on the token stream.
In terms of performance, tokenizing means that you kind of parse the input (at least) twice, first directly and then chunked into tokens.
If you want error messages that point back to their original source location, you then also need to maintain some kind of mapping from your token stream back to your original input.

Furthermore, while parser combinator libraries might _support_ custom token streams, they are rarely _optimized_ for them, more on which later.

### The case for tokenization

The first and primary reason for tokenizing is the separation of concerns.
One way or another, you will need to take care not to make any lexical errors.
As a simple example, looking for the keyword `let` is not as simple as looking for that sequence in the input stream, since that would also consume the first part of `letter`.
So, you typically end up writing tokenization logic no matter what.

The question then is just to what degree it's interwoven with the rest of the parsing code.
Parsing can be hard enough by itself, so beyond a certain complexity threshold completely separating the tokenization pass introduces a welcome separation of concerns.
Where that threshold lies for you is something you have to decide for yourself.
In my case it seemed annoying at first, but once implemented having an interface that is completely free of lexical concerns is so much nicer that it's a clear winner.

The second reason you might want to tokenize is that it can actually _improve_ performance.
As soon as you start doing backtracking you are, by definition, going to consume the same input multiple times.
With a separate tokenization pass, even if you _parse_ multiple times, at least you never _tokenize_ more than once.
This tokenization can actually be fairly expensive, especially when you have long comments, error handling, or complicated source position tracking logic.
So, for non-trivial parsers, separately tokenizing can be (and in my case _was_) many times faster.

### How to tokenize

You can easily write a tokenizer using any parser combinator library.
As far as they're concerned, it's just another parser.
However, if you've decided to do a separate tokenization pass anyway it might be worth looking into [`alex`](https://www.haskell.org/alex/).
`alex` allows you to write your token definitions with a regex-like syntax, and it will generate an optimized tokenizer from it.
It is commonly used in conjunction with `happy`, but it can be used equally well just by itself.

`alex` is very flexible, and depending on how you use it, can be _stupid_ fast.
Besides performance guarantees, you also get some degree of static analysis on your tokens.
I recommend trying it out, it's a much less committal choice than choosing whether you're using `happy` or not.

It's very simple to use; similar to `happy` you just add `build-tool-depends: alex:alex` to your `.cabal` file, and you can now use `.x` files as normal Haskell modules.
It ships with a few "wrappers", which provide the glue code between the generated code and the rest of your project.
These wrappers can be somewhat annoying to use, but fortunately, it's actually really easy to just write the glue code yourself.

It requires only two definitions (the `AlexInput` type and `alexGetByte` function), and gives you more control over performance and source position tracking.
From there, you just stream the result of the `alexScan` function, and you're good.
For illustration, this is the code that I ended up using.
It operates on raw `ByteString`s, and gives you line and column numbers per token.

```haskell
data AlexInput = AlexInput ByteString Int Int

alexGetByte :: AlexInput -> Maybe (Word8, AlexInput)
alexGetByte (AlexInput bs line col)
  | BS.null bs = Nothing
  | otherwise = Just $
      let b = BS.unsafeHead bs
          (line', col') = if isNewLine b then (line + 1, 0) else (line, col + 1)
       in (b, AlexInput (BS.unsafeTail bs) line' col')
```

## What parser combinator library to use

At this point, you should have some idea of which of these three options you want:

- Tokenizer + parser generator
- Tokenizer + parser combinators
- Parser combinators all the way down

In the first case, you don't really get much choice; you're using `alex` + `happy`.
The other two options, however, require you to choose from Haskell's vast collection of parser combinator libraries.
My knowledge of that landscape is fairly limited, but here are some recommendations anyway.

### Parser combinators all the way down

My general advice here has always been that for non-trivial parsing of raw textual input, you can't go wrong with `megaparsec`.
It's fast, well-documented, has good error messages, and with [Mark's tutorial](https://markkarpov.com/tutorial/megaparsec.html) it's very easy to pick up.
Other libraries may be faster, or have more elaborate error messages, but never both.

### Tokenizing + parser combinators

This is where things get interesting.

You can obviously use any parser combinator library that supports custom input streams.
From the ones I know, I find that `parsec` is actually best at this.
`megaparsec` can do it too, but its interfaces really emphasize non-tokenized inputs, which can make it a bit unwieldy.

If you're not already using either of those for tokenizing, however, I think it's worth considering writing a parser combinator library yourself.
They're really simple, the code it takes to write them is barely longer than the code it would take to integrate an existing parser.
The advantage is that you get a lot of fine-grained control over performance and error-handling.

For example, in my case, I store my tokens in a vector, so the parser state consists of just an index into that vector.
This makes it fast, since your streaming logic is just incrementing that integer.
The `Alternative` instance _always_ backtracks, but to still get good error messages it maintains the messages of whatever branch made the most progress while parsing.
All in all, it's about 40 lines of code, yet it's almost _three_ times as fast as the original all-`megaparsec` parser.

## Conclusion

It's interesting to see how different approaches to parsing "scale up".
For most simple parse jobs, you really don't need much more than a simple parser combinator library.
For more complex grammars, I recommend tokenizing and then running either `happy` or some sort of custom parser on top.
Ultimately, it depends on the project and its requirements, but this should at least have given you some idea of the options you have available.
