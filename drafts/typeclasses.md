---
title: Type Classes
subtitle: Effective Haskell 1
abstract:
  Type classes are horrible and you should not use them.
tags:
  effective haskell typeclass
---
 
> Small is beautiful, but simple ain't easy
>
> -- <cite>Joshua Bloch - Preface to Effective Java 3^rd^ edition</cite>

Over the past few months, there has been a surge of essays that essentially have the same message:
If you don't [constrain yourself](https://www.tweag.io/posts/2019-02-13-types-got-you.html), you can write inaccessible, unmaintainable, or incomprehensible code just as well in Haskell as in any other language.
Instead, let's all try to write [Simple Haskell](https://www.simplehaskell.org/), [Junior Haskell](https://www.parsonsmatt.org/2019/12/26/write_junior_code.html), or [Boring Haskell](https://www.snoyman.com/blog/2019/11/boring-haskell-manifesto).

As much as I love GADTs, I share the sentiment of the above posts.
Without the "avoid success at all costs" motto, Haskell would not have been what it is today.
In production, however, avoiding success at all costs is not a viable philosophy.
Nobody wants to read a paper to make sense of the code you wrote.
Professional, responsible software engineering is not about being smart, it's about being wise.

My issue with the posts above is this: _actually writing_ "Simple", "Junior", or "Boring" Haskell is neither simple, junior, nor boring.
And so, here's my attempt to bridge that gap.
My target audience is anybody struggling to effectively solve problems in Haskell, whether that's because they don't know enough Haskell (i.e. myself, 5 years ago), or know enough Haskell to over-engineer (i.e. myself, 2 years ago).
If I write these for myself 2 years ago, that should warn you that me 2 years from now might have a post lined up disagreeing with everything I write here.
Therefore, I welcome suggestions and feedback on [github](https://github.com/jonascarpay/blog) or [twitter](https://twitter.com/jonascarpay).

On to today's subject.

# Introduction

If programming to you is more than just a means to an end, which seems to often be the case with Haskell programmers, then you have probably heard of a small language called Smalltalk.
It is famous for many things, like being one of the first object-oriented languages, [taking second place in a popularity contest 45 years after its first release](https://insights.stackoverflow.com/survey/2017#technology-most-loved-dreaded-and-wanted-languages), and for my dad not shutting up about it from the moment I first touched GoF.
As influential as Smalltalk has been, it is also [famous for being misunderstood](http://wiki.c2.com/?AlanKayOnMessaging).
See, the point of object-oriented programming was never the objects, it was the message-passing style of programming.
It is that fatal misunderstanding why so much of Smalltalk's progeny makes up the "most dreaded" section of that very same popularity contest.

Keep this story in mind as we talk about today's subject: type classes.

There is no doubt that Haskell's type classes are a powerful tool
They're simple, but solve a large variety of problems.
They allow you to extend existing data with new behavior and extend existing behavior to new data.
They do code organization, they can be used to write type-level machinery, they can be used to not write value-level machinery.

Type classes are arguably Haskell's most influential feature, and it has _plenty_ of candidates.
If you look at modern programming languages, many of them have some notion of type classes, although usually with a different name.

Despite this, in my professional Haskell career, _the number of type classes I have written in production code can be counted on one hand_.
It seems that type classes are often misunderstood, resulting in code that is to Haskell as Java is to Smalltalk.
In many libraries on Hackage, type classes cause more trouble than they're worth, and in fact, I would go so far as to say that they are a code smell.

I am far from the first person to make this argument, and I'm not here to complain and act smug.
In this post, I will discuss

1. what type classes are and what problem they solve
2. when you should use them
3. when you should _not_ use them, and what you should do instead

Despite the first point, I'm going to assume that you have some basic understanding of how a type classes.
If you have read a beginner Haskell text and wrote a type class instance, you should be good, and you haven't, go do that first.

# What _is_ a type class, really?

In this section, I'm going to convince you that type classes are just implicit dictionaries.
If that seems logical to you, skip this section.

## Dictionaries

Say you were using some dialect of Haskell in which type classes do not exist.
How could you emulate them?
The answer is by using dictionaries.
Let's start by implementing our own `Monoid`.

### Classes

A class declaration becomes a data type declaration instead.
Instead of writing
```haskell
class Monoid m where
  mempty :: m
  mappend :: m -> m -> m
```
we define it as follows:
```haskell
data Monoid' m = Monoid'
  { mempty' :: m
  , mappend' :: m -> m -> m
  }
```
I'm ticking the names of our imitation type classes and methods to distinguish them, but you could of course call them anything you want.

`Monoid'` here is called a _dictionary_.
Dictionaries are really just data types, but we give them a special name to emphasize that it's a product type whose records might be functions.

For higher order types we'll need to turn on `RankNTypes`, but other than that it's the exact same thing:
```haskell
data Functor' f = Functor'
  { fmap' :: forall a b. (a -> b) -> (f a -> f b) }
```

### Instances

If classes are now types, instances are normal Haskell values.
So,
```haskell
instance Monoid [a] where
  mempty = []
  mappend = (++)
```
now becomes
```haskell
listMonoid :: Monoid' [a]
listMonoid = Monoid'
  { mempty' = []
  , mappend' = (++)
  }
```
Our instance is now explicitly named `listMonoid`.
We'll get into why that might be a good or bad thing later.
For now, consider that the two monoids on the integers don't need `newtype` wrappers:
```haskell
intProductMonoid, intSumMonoid :: Monoid' Int
intSumMonoid = Monoid' 0 (+)
intProductMonoid = Monoid' 1 (*)
```

### Constraints

Now that we have instances, how do we use them?
Turning a function with a type class constraint into one that uses a dictionary is easy; **change the `=>` into a `->`**.
For example,
```haskell
mconcat :: Monoid a => [a] -> a
mconcat [] = mempty
mconcat (a:as) = mappend a (mconcat as)
```
becomes
```haskell
mconcat' :: Monoid' a -> [a] -> a
mconcat' (Monoid' mempty' _) [] = mempty'
mconcat' (Monoid' _ mappend') (a:as) = mappend' a (mconcat' as)
```
In other words, we have turned the constraint into an argument.

That's really all you need to know, but here are two exercises to try if all of this feels weird to you.

First, define the equivalent of the instance `(Monoid a, Monoid b) => Monoid (a,b)`.
We haven't touched upon how you do constraints on instances, but the principle is the exact same as constraints on functions.

Once you've done that, copy the `Functor'` definition from above, define a dictionary-style `Applicative'`, and write the instances for `[]`.
I recommend ignoring the `Functor` constraint on `Applicative` at first, consider it extra credit.

Answers:
```haskell
tupleMonoid :: (Monoid' a, Monoid' b) -> Monoid' (a,b)
tupleMonoid (Monoid' memptyA mappendA, Monoid' memptyB mappendB) = Monoid memptyAB mappendAB
  where
    memptyAB = (memptyA, memptyB)
    mappendAB (a1,b1) (a2,b2) = (mappendA a1 a2, mappendB b1 b2)

data Applicative' f = Applicative'
  { functor :: Functor' a -- Extra credit if you got this
  , pure' :: forall a. a -> f a
  , (<+>) :: forall a b. f (a -> b) -> f a -> f b
  }

listFunctor :: Functor' []
listFunctor = Functor' map

listApplicative :: Applicative' []
listApplicative = Applicative' listFunctor (\x -> [x]) (\fs xs -> [f x | f <- fs, x <- xs])
```

If you feel like you need more practice, try also doing `Monad`, and write instances for, say `Maybe` or `Either e`.
You don't actually need to hand-write the implementations if you don't want to, you can just pull them from the existing type classes like so: `listApplicative = Applicative' listFunctor pure (<*>)`.

### Implicit dictionary passing

The point of the previous section is this: type classes are very similar to simple dictionary passing.
In fact, _under the hood_, instances _are_ just dictionaries.
The question then becomes, how are they different?

The answer is simple; with a `=>` the left-hand side, the dictionary gets picked automatically, and with a `->`, you have to pass it yourself!
This is an important point and the crux of this essay, so it bears repeating: **type classes are implicit dictionary passing.**

If you spend enough time around functional programmers, you'll eventually hear one boast that functional programming/lambda calculus wasn't invented as much as it was discovered.
The bolder ones might even posit that therefore the same applies to Haskell, and there is some truth to that.
However, if we were to place Haskell's features on a spectrum from "discovered" to "invented", I think few people would disagree that `->`, being part of even the simply typed lambda calculus, is further towards the "discovered" end of the spectrum than `=>`.

This is not a condemnation at all, Haskell is not a minimalist language, and the people who decided to include `=>` had very good reasons for doing so!
But I think it _is_ important to stop and ask yourself, if the merit of functional programming is its proximity to mathematics, why would you want to move towards the "invented" end of the spectrum?
Why do we want to introduce this special type of function arrow, one in which we don't get to control the argument?
If type classes are just implicit dictionary passing, what do we really care about; the implicitness or the dictionary passing?

## Uniqueness

As you probably know, a type instance needs to be unique; for example, there can only be one `Functor []`.
This makes sense, if the left-hand side of the `=>` is implicit, there has to be one and only one way to construct it.

### Uniqueness

This is also

## good
 - support syntax
     monad
     enum
     num
 - tells you about the implementation

## Bad

- cannot change

- unused methods

- fixed hierarchy

- newtypes just to change

- mocking
  `MonadIO m -> m a` instead `(FilePath -> m Foo) -> m a` or even `(IO a -> m a) -> m a`
