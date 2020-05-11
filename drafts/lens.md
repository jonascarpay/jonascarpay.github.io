---
title: Lessons from the Lens
subtitle: Effective Haskell 1
abstract:
  Turns out lenses are cool.
tags:
  haskell
---

> Small is beautiful, but simple ain't easy
>
> -- <cite>Joshua Bloch - Preface to Effective Java 3^rd^ edition</cite>

Over the past few months, there has been a surge of essays that essentially have the same message:
If you don't [constrain yourself](https://www.tweag.io/posts/2019-02-13-types-got-you.html), you can write inaccessible, unmaintainable, or incomprehensible code just as well in Haskell as in any other language.
Instead, let's all try to write [Simple Haskell](https://www.simplehaskell.org/), [Junior Haskell](https://www.parsonsmatt.org/2019/12/26/write_junior_code.html), or [Boring Haskell](https://www.snoyman.com/blog/2019/11/boring-haskell-manifesto).

As much as I love GADTs, I share the general sentiment of the above posts.
Without the "avoid success at all costs" motto, Haskell would not have been what it is today, but in production, avoiding success at all costs is not a viable strategy.
Nobody wants to read a paper just to make sense of the code you wrote.
Professional, responsible software engineering is not about being smart, it's about being wise.
That's as far as I'll repeat the arguments, you can find more in the posts above.

My point of contention is this: _actually writing_ "Simple", "Junior", or "Boring" Haskell is neither simple, junior, nor boring.
So, here's my attempt to bridge that gap.
This is a series of posts in which I will convey some of the lessons I have learned writing Haskell both as a hobby and professionally.
My target audience is anybody struggling to effectively solve problems in Haskell, whether that's because they

  - don't know enough Haskell (i.e. myself, 5 years ago)
  - know enough Haskell to over-engineer (i.e. myself, 1-2 years ago)

In this first edition, we will be looking at what I consider to be the gold standard of Haskell abstractions:  what it is, what makes it good, and what other lessons we can learn from it.

## Some disclaimers

Before I start:

  - This post is not about the [lens library](https://hackage.haskell.org/package/lens), at least not necessarily.
  - It is just as much about the lens' big brother, the _traversal_. In some sense it is about lens<em>likes</em> in general, but I think the lens and traversal together capture the spirit of what I want to communicate.
  - If I write these for myself 1-2 years ago, that should warn you that me 1-2 years from now might have a post lined up disagreeing with everything I write here.
  - Suggestions go on [github](https://github.com/jonascarpay/blog), questions/announcements on [twitter](https://twitter.com/jonascarpay)

# What is a lens?

Lenses have a lot of history behind them, that for the purposes of this post is irrelevant.
When I say lens, I specifically mean the Van Laarhoven formulation of the lens.
This is what it looks like:

```haskell
type Lens      s t a b = forall f. Functor     f => (a -> f b) -> (s -> f t)
type Traversal s t a b = forall f. Applicative f => (a -> f b) -> (s -> f t)
```

All the discussion around lenses, the notorious size of it's eponymous library tend to hide the fact that this is essentially it; a type signature.
Despite this, lenses can be intimidating and [a lot of people struggle with them](https://stackoverflow.com/search?q=lens+haskell).
So before I get into the _why_, I want to share a method I have used successfully to teach people about lenses in the past.

## You could have invented lenses

Let's start with a simple premise: we have a data type, and a function that allows us to make changes to part of it.
The data types have some fields, and we are going to define some functions to set/modify those fields.

```haskell
data Position = Position
  { getX :: Double
  , getY :: Double
  } deriving Show

data Unit = Unit
  { getName :: String
  , getHealth :: Int
  , getPosition :: Position
  } deriving Show

modifyPosition :: (Position -> Position) -> (Unit -> Unit)
modifyPosition f (Unit n h p) = Unit n h (f p)

modifyX :: (Double -> Double) -> (Position -> Position)
modifyX f (Position x) = Position (f x)
```

The second pair of brackets in the type signatures of those functions may seem superfluous, and they technically are, but they serve to highlight an important point.

### Endomorphisms and the dot

Both `modifyPosition` and `modifyX` can be seen as taking a function that operates on _part of_ the data structure, and lifting it to apply to the _entire_ structure.

Without that second pair of brackets, it not have been nearly as apparent that we can now do this:
```haskell
(position.x) :: (Double -> Double) -> (Unit -> Unit)
```
Using normal function composition with `.`, lenses now look like object-oriented style field accessors.
Note that this would not have been possible if

- rather than `modify`, our function would have been just a simple _setter_, e.g. of type `Position -> Unit -> Unit`.
  We _can_ still set, of course, by simply ignoring the old value.
- our arguments were in a different order, like `Unit -> (Position -> Position) -> Unit`

Furthermore, this works with multiple values:

```haskell
data Party :: Party { _members :: [Unit] }

modifyMembers :: (Unit -> Unit) -> (Party -> Party)
modifyMembers f (Party m) = Party (fmap f m)

resetPartyX :: Party -> Party
resetPartyX = (members.position.x) (const 0)
```

Functions of shape `a -> a` are called _endomorphisms_ and, as a rule of thumb, tend to compose nicely.
Haskell is full of endomorphisms.
For example, `fmap` can be an endomorphism, and it allows us to simplify the above example to this:
```haskell
type Party = [Unit]

members :: (Unit -> Unit) -> (Party -> Party)
members = fmap
```

Ultimately though, finding these sorts of symmetries is something you have to develop a feel for.
They can massively simplify code if you find a good one and they often have cool names, but if you force it you'll end up continuously rewriting or worse, forcing new code into the straitjacket of your pet abstraction.
In fact, moving from our current pre-lenses to proper lenses is all about _not_ having them be endomorphisms.

### From setter to getter


Let's start by making a change to `position` and `x` that doesn't actually change anything:
```haskell
newtype Identity a = Identity {runIdentity :: a}
  deriving Functor

positionId :: (Position -> Identity Position) -> (Unit -> Identity Unit)
positionId f (Unit n h p) = Unit n h <$> f p

xId :: (Double -> Identity Double) -> (Position -> Identity Position)
xId f (Position x y) = flip Position y <$> f x

set :: ((x -> Identity x) -> (y -> Identity y)) -> x -> y -> y
set f x = runIdentity . f (const Identity b))
```
The `Identity` functor (you can also just import it from `Data.Functor.Identity`), is the most boring possible functor; it just contains a single copy of its argument.
`positionId` and `xId`, you will probably agree, are therefore for all intents and purposes identical to `position` and `x` respectively.
They still compose the exact same way, and while `set` has to do a little more effort to wrap and unwrap, it still functions the same way.

The only thing to remark is that nothing we do in `positionId` and `xId` is particular to `Identity`, so we might as well make them a little more polymorphic:
```haskell
positionF :: Functor f => (Position -> f Position) -> (Unit -> f Unit)
positionF f (Unit n h p) = Unit n h <$> f p

xF :: Functor f => (Double -> f Double) -> (Position -> f Position)
xF f (Position x y) = flip Position y <$> f x
```
We only made them more polymorphic, they work with `set` just the same way.
But now, we can also do this:
```haskell
newtype Const c a = Const { runConst :: c }
  deriving Functor

get :: ((x -> Const y x) -> (y -> Const y y)) -> y -> x
get f = runConst . f Const

getX :: Unit -> Double
getX = get (positionF.xF)
```
That's right, we made a lens.


# Notes

Things I like

- just one extension
- we hide variables
  - constrains the number of valid implementations
  - expands what the caller can do with it
  - leverages the power of the functor/applicative
  - 
- composes beautifully
- we didn't even import anything

Lessons

- simple, but complex
  - took many years
- Length-preserving list

Also mention

- store/costate comonad coalgebra
  - true
  - pointless
  - smart
  - not wise
- laws
  - sort of pointless
  - it's just a type signature, it's not like every time you write a function of this type you now have to abide by the law
  - try writing a non-law abiding lens
