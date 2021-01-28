---
title: The working programmer's guide to setting up a Haskell project
date: 2021-01-28
tags: haskell nix project cabal hls
abstract: How to set up a Haskell project using Haskell.nix
---

**tl;dr:** 
Nothing beats Haskell.nix for features and flexibility.
To get started quickly, use the [template-haskell](https://github.com/jonascarpay/template-haskell) project template.

- Clone it to a directory with a name of your choice and `cd` into it
- Run `./wizard.sh`
- Enter the shell
- Start coding

---

If you've ever tried to set up a Haskell project, you know that it can be extremely frustrating to get to a point where everything just werks[^1].
Of course, just compiling a project is not _that_ hard, it's when you have multiple projects, spanning multiple compiler versions, all requiring tooling compiled with the right GHC version, that things quickly turn into a mess.
In this post I will outline what I think is currently the best way of setting up a Haskell project.

[^1]: Actually applies to every language

If you're just starting out with Haskell, this guide is not for you.
You're probably best off just using [Stack](https://www.fpcomplete.com/haskell/get-started/).
You will know when you're ready.

## The goal

This is what I consider project nirvana:

### No global state

GHC and tooling is far too sensitive to version issues and name clashes to have things globally installed.
Every project should have its own dedicated shell which contains the right tools.

### Modern tooling

When we enter our shell, all parts of a modern Haskell setup should be available.
By this I mean

- [`haskell-language-server`](https://github.com/haskell/haskell-language-server)
- [`ormolu`](https://github.com/tweag/ormolu)
- [`hoogle`](https://github.com/ndmitchell/hoogle)
- [`hlint`](https://github.com/ndmitchell/hlint)[^2]
- [`ghcid`](https://github.com/ndmitchell/ghcid)

All of these tools need to be compiled with the same version of GHC as the rest of your project.
We should be able to change the GHC version without breaking our tooling.

[^2]: `hlint` and `ghcid` are somewhat obviated by HLS, but I like having them around for CI and running tests, respectively.

### Minimal configuration

From deciding I want to make a project, to opening my editor and writing Haskell code cannot take more than 30 seconds.

## The solution

In my opinion, the key to get to this point is by using one of Haskell's best kept secrets, [IOHK's `haskell.nix`](https://github.com/input-output-hk/haskell.nix).
It is a collection of nix tools that are meant to replace the default Nix Haskell infrastructure.
It is well-documented, under active development, used in production, and most importantly, the only tool that comes close to allowing us to achieve the goals outlined above.

The way that Haskell.nix works is that you define a Stack or Cabal project as normal, but you let Haskell.nix take care of acquiring dependencies and tools, and setting up a development shell.

Fair warning, while you don't have to write a single line of nix code[^3], it helps a lot if you're at least familiar with the basics of nix.
I realize that is a non-starter for some people, and that's OK, we can still be friends.

[^3]: If you want to start from scratch you might need to copy and paste some Nix from the Haskell.nix manual.

### Why not just use...

#### ...Stack/Cabal
As mentioned in the intro, getting all your tools to work properly can be very finicky, since the tools and your project all need to be compiled with the same version of GHC.
Getting it tooling working for a single project can be tricky, let alone if you have multiple projects that have different versions of GHC.
Haskell.nix makes this a non-issue.

#### ..."Pure" Nix
Haskell.nix basically automatically takes care of everything you need to do when setting up a Haskell project in Nix.
Look at any of the myriad Haskell + Nix tutorials to see how involved that can get.

## Setup

### Preliminary setup
First, you need the [nix package manager](https://nixos.org/).

Second, you need to set up the [IOHK binary cache](https://input-output-hk.github.io/haskell.nix/tutorials/getting-started/#setting-up-the-binary-cache).
_Technically_ this is optional, but if you don't you will build GHC from scratch, which takes... a while.

### Project setup
Unlike, say, Stack, Haskell.nix is just a Nix library, it doesn't have any fancy CLI tools that create a project for you.
For that reason, you probably want to use a project template that you copy whenever you start a new project.

You can make one, described below, if you want that learning experience, but you can also just use [template-haskell](https://github.com/jonascarpay/template-haskell).

#### Using [template-haskell](https://github.com/jonascarpay/template-haskell)

Run these commands, replacing <my-project> with whatever you want your project to be called.
```bash
git clone https://github.com/jonascarpay/template-haskell <my-project>
cd <my-project>
./wizard.sh
```

`wizard.sh` will prompt you for your info, replace all placeholders, and reinitialize the git history.

From here, enter the shell and you should have all tools available to you.
If you want to change the GHC version, you can do so by changing the string in `pkgs.nix`.

#### Making one yourself
As mentioned before, Haskell.nix works _on top_ of either a `stack.yaml` or `cabal.project` project definition.
You don't need the tools _themselves_, but you will need a valid project.
So the first order of business is to set that up.
It doesn't really matter how you do this (you probably already have a preferred way already).

Once done, you need to set up `Haskell.nix`.
This is typically done by adding two Nix files; one that describes the project, and one that describes your development shell.
The Haskell.nix manual has clear instructions for both parts, see [Scaffolding](https://input-output-hk.github.io/haskell.nix/tutorials/getting-started/#scaffolding) and [How to get a development shell](https://input-output-hk.github.io/haskell.nix/tutorials/development/#how-to-get-a-development-shell).

Once you've set up your project and shell, you can pretty much share these two files between all your projects.

For reference, here are my [`pkgs.nix`](https://github.com/jonascarpay/template-haskell/blob/master/pkgs.nix)(called `default.nix` in the manual) and [`shell.nix`](https://github.com/jonascarpay/template-haskell/blob/master/shell.nix).

To turn your project into an actual template, you can get as fancy as you want.
As mentioned above, in `template-haskell`, I just use a simple shell script, but if you want you could also use [cookiecutter](https://github.com/cookiecutter/cookiecutter).

## Adding files

At this point, I should note that by default, **Haskell.nix only sees files that are known to git.**
They can have changes, but a new file that has not at least been staged is completely invisible to Haskell.nix.
If you run into issues building or entering the shell, always first make sure that at all relevant files have at least been staged.

## Building

You actually have two ways of building a project; purely with Nix or with Nix + Cabal.
They have slightly different use cases, so it's probably a good idea to familiarize yourself with both.

### Building with Nix + Cabal

This is probably closest to what you are already familiar with, and the one you typically use during development.
You simply enter your project shell, and `cabal new-build` as normal:

```bash
$ nix-shell
nix-shell$ cabal new-build
```

Everything here is as normal, except for the fact that Cabal doesn't have to worry about package databases, resolving and compiling dependencies, or GHC versions.

### Building with Nix

Haskell.nix also provides pure Nix derivations for your project.
This means that instead of polluting your project directory with build artifacts, they end up in the Nix store, where they get garbage collected automatically.

There are two downsides, however:

- Nix cannot do incremental builds within a single package
- The Nix evaluation can add a few seconds of overhead.

That means that you typically don't want to use this during normal development, but it's great for CI, or things that you don't build often.

You build like this:

```bash
$ nix-build pkgs.nix -A hsPkgs.<my-project>.components.<component>
```

Where `<component>` is one of:
- `lib`
- `exes.<executable>`
- `tests.<testsuite>`
- `benchmarks.<bench>`

**Tip:** you can explore these from the Nix REPL like this:
```bash
$ nix repl
nix-repl> :l ./pkgs.nix
nix-repl> hsPkgs.<my-project>.components.|
```

If you then press tab, the completion shows you the available components.

## Troubleshooting

### Something doesn't work
Did you add everything to git?

### Nix evaluation is slow!
See [Materialization](https://input-output-hk.github.io/haskell.nix/tutorials/materialization/#materialization)

### The shell is slow!
See the point about Materialization above, or consider using [`cached-nix-shell`](https://github.com/xzfc/cached-nix-shell).

### Why is CI building GHC?

`template-haskell` also contains a CI matrix.
The Nix pipeline uses cachix to cache builds, specifically the `jmc` cachix.
You don't have push access to this, so if you change something that triggers a GHC change it will be rebuilt every time.
I recommend you create and set up your own personal cachix.

### I cannot rebuild without a network connection?

Without going into the details, this happens because the git-cleaned source file is itself a derivation that Nix will attempt to get from cache.
Simply build with `--option substituters ""` to disable cache lookup.
