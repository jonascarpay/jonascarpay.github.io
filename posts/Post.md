---
title: Monoidal Puzzle Solving
---

Judging by the recent surge in popularity of the excellent [Cracking the Cryptic YouTube channel](https://www.youtube.com/channel/UCC-UOdK8-mIjxBQm_ot1T-Q), I'm not the only person for who recent circumstances have led them to rediscover logic puzzles.
I always thought Sudoku's were boring, but as it turns out, they get a bad rep because most Sudoku's in newspapers and magazines are computer generated.
There is an entire art to designing these Puzzles, complete with world-famous "setters", and it makes for a perfect nerdy rabbit hole for people suddenly spending a lot of time inside.

Things become especially interesting when you start combining rule sets.
For example, you might have seen the "miracle Sudoku" with only 2 given digits when [this video](https://www.youtube.com/watch?v=yKf9aUIxdb4) hit the front page of a certain orange website, and even some newspapers.

The same goes for writing solvers.
Writing a Sudoku solver is trivial, but can we make one that can easily work with different rule sets, or even combine them?
After all, designing these puzzles is a lot easier if you can freely experiment with rules while making sure that you still have a unique solution.

So, in this post, we're going to write a general puzzle solver.
It won't be _as fast as possible_, but it will be plenty fast.
It also won't be optimized for Sudoku's in particular, but it will do a good job at them, and more importantly tackle other kinds of puzzles as well.
We also won't be using any fancy tools like propagators or constraint solvers, instead sticking to a simple backtracking algorithm.
That's a lot of "won't"s, but remember that making three 80/20 trade-offs is the same as making one $(80/20)^3=50/1$ trade-off.

Let's start.

# The solver

A rule tells us whether, given a _partial_ solution to a puzzle, we can put an answer `a` at some point/square/cell `i` (for _index_).
Once manage to assign an answer to _every_ cell in the puzzle, we have our solution.
```haskell
type Solution i a = i -> a
type Rule i a = Solution i (Maybe a) -> i -> a -> All
```
Using `All` instead of `Bool` here makes `Rule i a` our first monoid of the evening.
It gives us a way to compose rules basically for free, with `r1 <> r2` meaning that both `r1` and `r2` must hold.

For the initial given digits/answers, we'll keep it simple and just use a list of pairs.
```haskell
type Givens i a = [(i, a)]
```

We also need a way to list all inhabitants of our `i` and `a` types.
There are [libraries](https://hackage.haskell.org/package/universe) that do this for you, but I like to save the dependency and just leverage the `Ix`[^univ] type class from `base`.
```haskell
type Universe a = (Bounded a, Ix a)

universe :: Universe a => [a]
universe = range (minBound, maxBound)
```

[^univ]: If you're thinking why we don't just use `Enum` instead of `Ix`, it's because tuples don't have `Enum` instances, and we're going to be using a lot of tuples.

With the types taken care of, the solver becomes so simple it practically writes itself.
For each point, we try to assign an answer that satisfies the rule, and the list monad takes care of the backtracking:
```haskell
solve ::
  (Ord i, Universe i, Universe a) =>
  Rule i a ->
  Givens i a ->
  [Solution i a]
solve rule given = go (filter (`Map.notMember` m0) universe) m0
  where
    m0 = Map.fromList given
    go [] m = pure (m Map.!)
    go (i : is) m = do
      a <- universe
      guard . getAll $ rule (m Map.!?) i a
      go is (M.insert i a m)
```

### $n$ Queens

As an initial exercise/proof-of-concept, we'll try the classic $n$ queens problem.
The object is to place $n$ queens on an $n\times n$ chess board.
Our domain `i` is the indices of the columns of the board, and our range `a` is the row at which there is a queen in that column.
Both of these are numbers $0 \dots n-1$.
We'll use the `finite-typelits` to represent bounded finite integers[^ixinst].

[^ixinst]: `Finite` doesn't actually have an `Ix` instance [yet](https://github.com/mniip/finite-typelits/pull/19), so for now you'll have to import the `Data.Finite.Internal` module and add a standalone `deriving instance (Ix (Finite n))`.

The rule itself is simple.
To place a queen in $(x,y)$, none of the other columns can have a queen in row $y$ or any of the diagonals of $(x,y)$:
```haskell
difference :: KnownNat n => Finite n -> Finite n -> Finite n
difference a b = max a b - min a b

nqueens :: KnownNat n => Rule (Finite n) (Finite n)
nqueens f x y = All . and $ do
  qx <- universe
  qy <- toList (f qx)
  [qy /= y, difference qx x /= difference qy y]
```

If we now ask GHCi how many ways there are to place the $n$ queens on the board, we get the [expected](https://en.wikipedia.org/wiki/Eight_queens_puzzle#Counting_solutions) answers[^ghc]:
```
λ> length $ solve (nqueens @8) [] 
92
λ> length $ solve (nqueens @4) []
2
λ> length $ solve (nqueens @12) []     
14200
```

[^ghc]:
Once you get up to $n=12$ GHCi definitely starts to sputter.
Compiling will make things orders of magnitude faster.

# Sudoku

One thing that will come up _a lot_ in these puzzles is the concept of a cell "seeing" other cells.
For example, in normal Sudoku rules a cell "sees" all cells in its row, column, and $3 \times 3$ box:

```haskell
type Sees i = i -> Set i

row :: (Universe x, Ord y) => Sees (x, y)
row (_, y) = Set.fromList $ (,y) <$> universe

column :: (Universe y, Ord x) => Sees (x, y)
column (x, _) = Set.fromList $ (x,) <$> universe

type F9 = Finite 9

box :: Sees (F9, F9)
box = Set.fromList . bitraverse (group 3) (group 3)
  where
    group n d = let b = div d n * n in [b .. b + (n -1)]
```

`Sees` is another monoid we get for free, which again works out nicely:
```
λ> (column <> row <> box) (3,2)
fromList [(0,2),(1,2),(2,2),(3,0),(3,1),(3,2),(3,3),(3,4),(3,5),(3,6),(3,7),(3,8),(4,0),(4,1),(4,2),(5,0),(5,1),(5,2),(6,2),(7,2),(8,2)]
```

The single rule of Sudoku is that a cell must be unique among the cells that it sees.
We will call this concept of a property that holds between a cell and those it sees a _relation_, and together with `Sees` we can turn them into _rules_:
```haskell
type Relation a = a -> [a] -> All -- _another_ monoid

unique :: Eq a => Relation a
unique = (All .) . notElem

withSeen :: Sees i -> Relation a -> Rule i a
withSeen sees rel = go
  where
    go f i a = rel a $ Set.toList (sees i) >>= toList . f
```

With that, we can express the rules of Sudoku in two equivalent ways:
```haskell
sudokuRules :: Rule (F9, F9) F9
sudokuRules = withSeen row unique <> withSeen row unique <> withSeen row unique
sudokuRules = withSeen (row <> column <> box) unique
```

The only thing that's left is to find a Sudoku to solve.
I'll start using some functions whose implementations are neither interesting nor particularly relevant.
If you see a naked type signature its implementation can be found in the appendix.

```haskell
printSolution :: (Solution i a -> String) -> [Solution i a] -> IO ()
showGrid :: (Universe x, Universe y) => (a -> Char) -> Solution (x, y) a -> String
showF9 :: F9 -> Char
parseSudoku :: [String] -> Givens (F9, F9) F9

normalSudoku :: Givens (F9, F9) F9
normalSudoku =
  parseSudoku
    [ "5 3 .  . 7 .  . . .",
      "6 . .  1 9 5  . . .",
      ". 9 8  . . .  . 6 .",
      "8 . .  . 6 .  . . 3",
      "4 . .  8 . 3  . . 1",
      "7 . .  . 2 .  . . .",
      ". 6 .  . . .  2 8 .",
      ". . .  4 1 9  . . 5",
      ". . .  . 8 .  . 7 ."
    ]
```

And sure enough:
```
λ> printSolution (showGrid showF9) (solve sudokuRules normalSudoku)
5 3 4 6 7 8 9 1 2
6 7 2 1 9 5 3 4 8
1 9 8 3 4 2 5 6 7
8 5 9 7 6 1 4 2 3
4 2 6 8 5 3 7 9 1
7 1 3 9 2 4 8 5 6
9 6 1 5 3 7 2 8 4
2 8 7 4 1 9 6 3 5
3 4 5 2 8 6 1 7 9
```

### Anti-Knight Sudoku

With everything in place, we can try some Sudoku variations.
For example, one popular variation is anti-knight Sudoku, in which, in addition to the normal Sudoku rules, a cell cannot contain the same digit as any cell a chess knight's move away:

```haskell
fromOffsets :: KnownNat n => [(Integer, Integer)] -> Sees (Finite n, Finite n)
fromOffsets offsets (x, y) = Set.fromList $ do
  (dx, dy) <- offsets
  (,) <$> asInt (+ dx) x <*> asInt (+ dy) y
  where
    asInt f = maybe [] pure . packFinite . f . getFinite

knight :: KnownNat n => Sees (Finite n, Finite n)
knight = fromOffsets $ [(2, 1), (1, 2)] >>= bitraverse f f
  where
    f x = [x, -x]

antiknightSudoku :: Givens (F9, F9) F9
antiknightSudoku =
  parseSudoku
    [ ". 3 .  . 4 1  . . 7",
      ". . .  5 3 .  . 4 .",
      "4 . .  8 . 9  . 3 .",
      "6 . 3  . . .  . 7 .",
      ". . .  6 . 3  . . 4",
      ". 4 .  . . .  . . .",
      "3 . .  . . .  . . .",
      ". . .  . 6 .  . 5 .",
      ". 6 4  3 . .  . . ."
    ]

antiknightRules = sudokuRules <> withSeen knight unique
```

If we attempt to solve this with regular Sudoku rules it's ambiguous, but as expected, adding the antiknight rule gives us the following unique solution:
```
λ> printSolution (showGrid showF9) (solve antiknightRules antiknightSudoku)
5 3 6 2 4 1 8 9 7
9 7 8 5 3 6 2 4 1
4 2 1 8 7 9 6 3 5
6 1 3 4 8 5 9 7 2
7 8 9 6 2 3 5 1 4
2 4 5 9 1 7 3 6 8
3 5 7 1 9 8 4 2 6
8 9 2 7 6 4 1 5 3
1 6 4 3 5 2 7 8 9
```

### Miracle Sudoku

Let's try the "miracle" Sudoku we talked about in the introduction.
The "miracle" Sudoku has extremely few givens, but makes up for it in rules.
The rules are

  - Normal Sudoku
  - Antiknight
  - Anti<em>king</em>
  - No two consecutive digits can be orthogonally adjacent

No problem, we have almost everything we need already:
```haskell
miracleSudoku =
  parseSudoku
    [ ". . .  . . .  . . .",
      ". . .  . . .  . . .",
      ". . .  . . .  . . .",
      ". . .  . . .  . . .",
      ". . 1  . . .  . . .",
      ". . .  . . .  2 . .",
      ". . .  . . .  . . .",
      ". . .  . . .  . . .",
      ". . .  . . .  . . ."
    ]

miracleRules =
  sudokuRules
    <> withSeen (knight <> king) unique
    <> withSeen adjacent noConsecutive

king :: KnownNat n => Sees (Finite n, Finite n)
king = fromOffsets $ (,) <$> [-1 .. 1] <*> [-1 .. 1]

adjacent :: KnownNat n => Sees (Finite n, Finite n)
adjacent = fromOffsets [(0, -1), (0, 1), (1, 0), (-1, 0)]

noConsecutive :: KnownNat n => Relation (Finite n)
noConsecutive n = All . all ((/= 1) . difference n)
```

As for actually solving it, I highly recommend [trying it for yourself](https://cracking-the-cryptic.web.app/sudoku/tjN9LtrrTL), especially since GHCi will take a while.

With that, we've had enough Sudoku for a while, let's turn our attention to a few other puzzles.

# A Few Other Puzzles

### $n$ Queens, Bishops, and Rooks

Now that we're more familiar with how to write and compose rules, let's look back and have some fun with the $n$ queens problem.
We're going to express it differently this time, instead of mapping every column to a row with a queen, we'll express it as mapping every cell on the board to whether or not there is a queen there, similar to how we mapped each cell of a Sudoku to a digit.

```haskell
data Square = Piece | Empty
  deriving (Eq, Show, Bounded, Ix, Ord, Enum)

nonattacking :: Relation Square
nonattacking Empty _ = All True
nonattacking Piece xs = All (notElem Piece xs)

diagonals :: KnownNat n => Sees (Finite n, Finite n)
diagonals (x, y) = Set.fromList $ do
  d <- universe
  dx <- [x - d, x + d]
  let dy = y - d
  guard $ difference x dx == difference y dy
  pure (dx, dy)
```

With that, we have some more flexibility, like decomposing the rules into a combination of two different rule sets:

```haskell
nrooks :: KnownNat n => Rule (Finite n, Finite n) Square
nrooks = withSeen (row <> column) nonattacking

nbishops :: KnownNat n => Rule (Finite n, Finite n) Square
nbishops = withSeen diagonals nonattacking

nqueens :: KnownNat n => Rule (Finite n, Finite n) Square
nqueens = nrooks <> nbishops
```

```
λ> printSolution (showGrid showSquare) (solve (nrooks @8) [])
Ambiguous, first solution:
X . . . . . . .
. X . . . . . .
. . X . . . . .
. . . X . . . .
. . . . X . . .
. . . . . X . .
. . . . . . X .
. . . . . . . X
λ> printSolution (showGrid showSquare) (solve (nbishops @8) [])
Ambiguous, first solution:
X . . . . . . .
X . . . . . . .
X . . . . . . .
X . . . . X . X
X . . . . X . X
X . . . . . . .
X . . . . . . .
X . . . . . . .
```
If you look at the solution to `nbishops`, you might spot an issue.
The object of the original $n$ queens game is to place $n$ queens, but our backtracker's goal is to just assign `Empty` or `Piece` to every square.
In the case of `nbishops` you could place as many as 14 bishops, but we're not guiding the solver towards that point.
It becomes especially clear if we try `nqueens`:
```
λ> printSolution (showGrid showSquare) (solve (nqueens @8) [])
Ambiguous, first solution:
X . . . . . . .
. . . X . . . .
. X . . . . . .
. . . . X . . .
. . X . . . . .
. . . . . . . .
. . . . . . . .
. . . . . . . .
```
That won't do at all.
We _could_ filter every solution at the _end_ on whether or not it has a queen in every column, but that's more brute forcing than backtracking.
Instead we'll define a new combinator, called `constraint`.
It will place a constraint on a region by, when every cell in a region has been assigned a value, checking whether some condition holds for those values.

```haskell
constraint :: Eq i => Sees i -> ([a] -> All) -> Rule i a
constraint sees rel = go
  where
    go f i a =
      let f' i' = if i' == i then Just a else f i'
       in maybe (All True) rel . traverse f' . Set.toList . sees $ i
```

And with that, we can reformulate `nqeens`:

```haskell
contains :: (Eq i, Eq a) => Sees i -> a -> Rule i a
contains sees a = constraint sees (All . elem a)

nqueens2 :: KnownNat n => Rule (Finite n, Finite n) Square
nqueens2 = nrooks <> nbishops <> (column `contains` Piece)
```

```
λ> printSolution (showGrid showSquare) (solve (nqueens2 @8) [])
Ambiguous, first solution:
X . . . . . . .
. . . . . . X .
. . . . X . . .
. . . . . . . X
. X . . . . . .
. . . X . . . .
. . . . . X . .
. . X . . . . .
```
And as expected, we get a proper solution again.

### $n$tiknight Queens

The whole point was to experiment with composing new rule sets.
So, let's take a lesson from the Sudoku's, and consider a variant of $n$ queens in which the queens also cannot be within a knight's move from one another:

```
λ> printSolution (showGrid showSquare) (solve (withSeen knight nonattacking <> nqueens2 @8) [])
No Solutions
```
Turns out it doesn't actually have any solutions for $n=8$!
Instead we need to go to $n=10$ (or 1), but only if we don't also force a piece at (5,5):
```
λ> printSolution (showGrid showSquare) (solve (withSeen knight nonattacking <> nqueens2 @10) [])
Ambiguous, first solution:
. . . X . . . . . .
. . . . . . . X . .
X . . . . . . . . .
. . . . X . . . . .
. . . . . . . . X .
. X . . . . . . . .
. . . . . X . . . .
. . . . . . . . . X
. . X . . . . . . .
. . . . . . X . . .
λ> printSolution (showGrid showSquare) (solve (withSeen knight nonattacking <> nqueens2 @10) [((5, 5), Piece)])
No solutions
```

### Star Battle

And finally, my new favorite kind of puzzle: [Star Battle](https://www.youtube.com/watch?v=w1DSgHiI6GQ).
In a Star Battle, the object is to place two stars in every row, column, and outlined region, such that no two stars touch, even diagonally.

It may initially seem tricky to express the outlined regions, but it's simply another `Sees` relation.
Aside from that, we have all the tools we need to express the rules to star battle already.

```haskell
parseStarbattle :: (KnownNat n) => [String] -> Sees (Finite n, Finite n)

starbattleRules :: KnownNat n => Sees (Finite n, Finite n) -> Rule (Finite n, Finite n) Square
starbattleRules regions =
  withSeen king nonattacking
    <> has2 regions
    <> has2 column
    <> has2 row
  where
    has2 r = constraint r (All . (== 2) . length . filter (== Piece))

starbattle :: Sees (F10, F10)
starbattle =
  parseStarbattle
    [ "AAAAAABBBB",
      "ACADABBEEE",
      "ACCDDBEEEE",
      "ACCDDBEEEF",
      "ACGDDBEEEF",
      "ACGDHHEEFF",
      "AGGGHIIEEF",
      "JGGGHIIEFF",
      "JGGHHJIIFF",
      "JJJJJJIIFF"
    ]
```
```
λ> printSolution (showGrid showSquare) (solve (starbattleRules starbattle) [])
. . . X . . . . X .
. X . . . . X . . .
. . . . X . . . X .
X . X . . . . . . .
. . . . . . . X . X
. . . X . X . . . .
. X . . . . . . . X
. . . . X . X . . .
X . X . . . . . . .
. . . . . X . X . .
```
And that's how you solve a Star Battle.

# Conclusion

It may have looked like we were just solving puzzles, but there's a point to this post.
We never defined any data types (aside from `Square`), type classes, or functions more than a few lines long, and yet we were able to solve a wide variety of puzzles.

Haskell is at its best when you're able to keep things simple.
Higher-order functions are really really powerful, and using fancy types is more often than not a failure to express what you're doing in simple terms.

# Appendix: Omitted Code

```haskell
printSolution :: (Solution i a -> String) -> [Solution i a] -> IO ()
printSolution pp sols = putStrLn $ case sols of
  [] -> "No solutions"
  [x] -> pp x
  (x : _) -> "Ambiguous, first solution:\n" <> pp x

showGrid :: (Universe x, Universe y) => (a -> Char) -> Solution (x, y) a -> String
showGrid showA sol = ($ "") . unlines' $ showRow <$> universe
  where
    showRow y = showString . intersperse ' ' $ showA . sol . (,y) <$> universe
    unlines' = foldr (.) id . intersperse (showChar '\n')

showF9 :: F9 -> Char
showF9 = chr . (+ ord '1') . fromIntegral

parseSudoku :: [String] -> Givens (F9, F9) F9
parseSudoku strs = do
  (y, xs) <- zip [0 ..] strs
  (x, Just d) <- zip [0 ..] (fromChar <$> filter (/= ' ') xs)
  pure ((x, y), d)
  where
    fromChar :: Char -> Maybe F9
    fromChar c
      | c >= '1' && c <= '9' = Just . fromIntegral $ ord c - ord '1'
      | otherwise = Nothing

parseStarbattle :: KnownNat n => [String] -> Sees (Finite n, Finite n)
parseStarbattle strs = (groupPos M.!) . (posGroup M.!)
  where
    posGroup = M.fromList assocs
    groupPos = foldr (\(p, group) m -> M.insertWith (<>) group (Set.singleton p) m) mempty assocs
    assocs = do
      (y, line) <- zip [0 ..] strs
      (x, group) <- zip [0 ..] (filter (/= ' ') line)
      pure ((x, y), group)
```
