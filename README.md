# ordo

A small Ruby library that tells you where any date falls in the traditional
(English / 1928 American) **Book of Common Prayer** calendar — its season, the
day's principal observance, and a few ways to render it as a timestamp.

It runs two cycles in parallel, the way a real ordo does:

- **temporal** — the movable cycle anchored on Easter and Advent (Lent,
  Eastertide, the Sundays after Trinity, and so on)
- **sanctoral** — fixed-date feasts, seeded with the BCP red-letter days,
  which you can extend with your own calendar

When a feast collides with a Sunday or season, a rank-based precedence rule
decides which is the day's principal observance; the loser becomes a
commemoration, and a displaced higher feast is transferred forward.

It patches `Date` with a few convenience methods, so any date answers for
itself.

## Install

There's no gem — it's a single file. Drop `ordo.rb` next to your code and:

```ruby
require_relative "ordo"
```

Requires only the standard library (`date`).

## Quick start

```ruby
require_relative "ordo"
require "date"

Date.new(2026, 12, 27).liturgical_season   #=> :christmas
Date.new(2026, 12, 27).liturgical_label    #=> "Saint John, Apostle and Evangelist"
```

## The methods on `Date`

### `liturgical_season` → Symbol

The broad season. One of `:advent`, `:christmas`, `:epiphany`, `:pre_lent`,
`:lent`, `:easter`, `:trinity`.

```ruby
Date.new(2026, 1, 25).liturgical_season    #=> :epiphany
```

### `liturgical_label` → String

The day's principal observance as a full title — what actually outranks
everything else on that day.

```ruby
Date.new(2026, 12, 27).liturgical_label    #=> "Saint John, Apostle and Evangelist"
Date.new(2026, 5, 27).liturgical_label     #=> "Wednesday after Whitsunday"
```

Weekdays get proper **ferial** names — "Wednesday after the First Sunday after
Trinity" — rather than a bare season label.

### `liturgical_stamp(style:)` → String

A formatted timestamp. Four styles:

```ruby
d = Date.new(2026, 1, 25)

d.liturgical_stamp(style: :season)
#=> "Epiphanytide, A.D. 2026"

d.liturgical_stamp(style: :feast)
#=> "Conversion of St Paul, A.D. 2026"

d.liturgical_stamp(style: :colophon)
#=> "on the Conversion of St Paul, in the year of grace 2026"

d.liturgical_stamp(style: :almanac)
#=> "Conversion of Saint Paul
#    Epiphanytide · A.D. 2026 · g XIII · DL D"
```

`:colophon` is the old-book dateline; `:almanac` adds the computus data
(golden number `g` and dominical letter `DL`).

### `ordo` → `Ordo::Day`

The full resolution: season, principal observance with its rank, any
commemorations, and feasts transferred in from earlier days.

```ruby
Date.new(2026, 1, 25).ordo
#=> #<Ordo::Day 2026-01-25 season=epiphany
#     principal="Conversion of Saint Paul" (apostle)
#     commemoration="Third Sunday after the Epiphany">
```

On 25 January the apostle's feast outranks the ordinary Sunday after Epiphany,
so it takes the day and the Sunday drops to a commemoration.

## Adding your own feasts

The sanctoral comes seeded with the BCP red-letter days. Register more with
`Ordo.add`:

```ruby
Ordo.add(month: 7, day: 11, name: "Saint Benedict, Abbot",
         short: "Saint Benedict", rank: :lesser_festival)

Date.new(2026, 7, 11).liturgical_label    #=> "Saint Benedict, Abbot"
```

The fields:

- `name:` — the full rubrical title (shown in `:almanac` and `ordo`)
- `short:` — a terse form used in `:feast` and `:colophon` stamps (optional)
- `rank:` — precedence; highest to lowest: `:principal_feast`, `:holy_day`,
  `:festival`, `:apostle`, `:lesser_festival`, `:commemoration`
- `event:` — `true` for feasts that name an event rather than a person
  (the Annunciation, the Conversion of St Paul), which changes how the
  `:colophon` reads ("on the Annunciation" vs. "on the feast of Saint Andrew")
- `article:` — `:the` or `:none` to override how the colophon article is
  guessed, for the handful of names where guessing fails (Candlemas takes no
  article; the Conversion of St Paul takes "the")

### Keeping your calendar in one place

For a blog or app, put all your `add` calls in a separate file that becomes
the entry point, so the rest of your code never touches `ordo.rb` directly:

```ruby
# my_calendar.rb
require_relative "ordo"

Ordo.add(month: 7,  day: 11, name: "Saint Benedict")
Ordo.add(month: 5,  day: 6,  name: "Saint John before the Latin Gate",
         rank: :lesser_festival)
# ... the rest of your sanctoral ...
```

Then everywhere else just `require_relative "my_calendar"` and your feasts are
already registered.

## The other tradition

Passing `tradition: :american_1979` suppresses the pre-Lenten Gesima Sundays
(Septuagesima, Sexagesima, Quinquagesima), which the 1979 American BCP dropped
in favour of an ordinary-time model. The default, `:traditional`, keeps them.

```ruby
Date.new(2026, 2, 1).liturgical_label
#=> "Septuagesima"

Date.new(2026, 2, 1).liturgical_label(tradition: :american_1979)
#=> "Fourth Sunday after the Epiphany"
```

Every method takes the `tradition:` keyword.
