# frozen_string_literal: true

require "date"

# A small ordo for the traditional (English / 1928 American) BCP calendar.
#
# Two cycles run in parallel:
#   * temporal  — movable, anchored on Easter and Advent
#   * sanctoral — fixed-date feasts, seeded with the BCP red-letter days
#
# When they collide on a day, a rank-based precedence rule decides which is
# the day's principal observance; the loser becomes a commemoration, and a
# displaced higher feast is transferred to the next free day.
#
#   Date.new(2026, 1, 25).ordo
#   #=> #<Ordo::Day 2026-01-25 season=epiphany
#   #     principal="Conversion of Saint Paul" (apostle)
#   #     commemoration="Third Sunday after the Epiphany">
#
#   Date.new(2026, 1, 25).liturgical_label  #=> "Conversion of Saint Paul"
#
# Add your own feasts:
#   Ordo.add(month: 7, day: 11, name: "Saint Benedict", rank: :lesser_festival)
#
module Ordo
  module_function

  # --- ranks, highest precedence first ----------------------------------
  RANKS = %i[
    principal_feast
    holy_day
    festival
    apostle
    lesser_festival
    commemoration
  ].freeze

  def rank_value(rank) = RANKS.index(rank) || RANKS.size

  # =====================================================================
  # TEMPORAL CYCLE
  # =====================================================================

  # Anonymous Gregorian Computus.
  def easter(year)
    a = year % 19
    b, c = year.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month = (h + l - 7 * m + 114) / 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    Date.new(year, month, day)
  end

  # First Sunday of Advent = 4th Sunday before Christmas.
  def advent_sunday(year)
    christmas = Date.new(year, 12, 25)
    offset = christmas.wday.zero? ? 7 : christmas.wday
    christmas - (offset + 21)
  end

  # The civil year whose Easter governs `date`.
  def governing_easter_year(date)
    date >= advent_sunday(date.year) ? date.year + 1 : date.year
  end

  def season(date, tradition: :traditional)
    easter        = easter(governing_easter_year(date))
    ash_wednesday = easter - 46
    septuagesima  = easter - 63
    pentecost     = easter + 49
    epiphany      = Date.new(date.year, 1, 6)
    gesimas       = tradition != :american_1979

    return :christmas if date >= Date.new(date.year, 12, 25)
    return :christmas if date < epiphany
    return :advent    if date >= advent_sunday(date.year)
    return :epiphany  if date < (gesimas ? septuagesima : ash_wednesday)
    return :pre_lent  if gesimas && date < ash_wednesday
    return :lent      if date < easter
    return :easter    if date <= pentecost

    :trinity
  end

  SEASON_RANK = {
    advent: :privileged, lent: :privileged,
    christmas: :ordinary, epiphany: :ordinary,
    pre_lent: :ordinary, easter: :privileged, trinity: :ordinary
  }.freeze

  # The temporal observance for a date, as a feast-like hash so it can be
  # ranked against the sanctoral. Principal feasts are flagged so they win.
  def temporal(date, tradition: :traditional)
    easter = easter(governing_easter_year(date))

    principals = {
      easter        => "Easter Day",
      (easter + 39) => "Ascension Day",
      (easter + 49) => "Whitsunday",
      (easter + 56) => "Trinity Sunday",
      Date.new(date.year, 12, 25) => "Christmas Day",
      Date.new(date.year, 1, 6)   => "The Epiphany"
    }
    if (name = principals[date])
      return { name: name, rank: :principal_feast, kind: :temporal }
    end

    s = season(date, tradition: tradition)
    name = named_temporal(date, easter, s, tradition)
    privileged = SEASON_RANK[s] == :privileged && date.wday.zero?

    { name: name, rank: privileged ? :festival : :commemoration,
      kind: :temporal, season: s, sunday: date.wday.zero? }
  end

  WEEKDAY = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze

  def named_temporal(date, easter, s, tradition)
    # Named days that override both Sunday and ferial naming.
    gesima = {
      (easter - 63) => "Septuagesima", (easter - 56) => "Sexagesima",
      (easter - 49) => "Quinquagesima"
    }
    gesima.clear if tradition == :american_1979
    return gesima[date] if gesima.key?(date)
    return "Ash Wednesday" if date == easter - 46
    return "Palm Sunday"   if date == easter - 7

    # The Sunday on or before this date governs the week.
    owning_sunday = date - date.wday
    sunday = sunday_name(owning_sunday, easter, tradition)

    return sunday[:bare] if date.wday.zero? # the date *is* the Sunday

    # Ferial weekday: "Wednesday after the First Sunday after Trinity".
    "#{WEEKDAY[date.wday]} after #{sunday[:connective]}"
  end

  # Name the given Sunday within its season, returning both a bare label
  # ("First Sunday after Trinity") and the connective form used after
  # "Monday after …" ("the First Sunday after Trinity"). Whitsun-week is
  # special: it belongs to Pentecost, not "after Easter".
  def sunday_name(sunday, easter, tradition)
    bare = sunday_label(sunday, easter, tradition)
    # Proper-noun Sundays take no connective article ("after Trinity Sunday").
    no_article = %w[
      Septuagesima Sexagesima Quinquagesima
    ].include?(bare) || bare.match?(/\A(Trinity Sunday|Easter Day|Whitsunday|Palm Sunday)\z/)
    connective =
      if no_article
        bare
      else
        # "The Epiphany" -> "the Epiphany"; "First Sunday..." -> "the First Sunday..."
        "the #{bare.sub(/\AThe /, "")}"
      end
    { bare: bare, connective: connective }
  end

  def sunday_label(sunday, easter, tradition)
    return "Septuagesima"  if sunday == easter - 63 && tradition != :american_1979
    return "Sexagesima"    if sunday == easter - 56 && tradition != :american_1979
    return "Quinquagesima" if sunday == easter - 49 && tradition != :american_1979
    return "Palm Sunday"   if sunday == easter - 7
    return "Easter Day"    if sunday == easter
    return "Whitsunday"    if sunday == easter + 49
    return "Trinity Sunday" if sunday == easter + 56
    return "The Epiphany"  if sunday == Date.new(sunday.year, 1, 6)

    case season(sunday, tradition: tradition)
    when :christmas then "Sunday after Christmas"
    when :trinity
      n = ((sunday - (easter + 56)).to_i / 7)
      "#{ordinal(n)} Sunday after Trinity"
    when :epiphany
      fsa = first_sunday_after(Date.new(sunday.year, 1, 6))
      n = ((sunday - fsa).to_i / 7) + 1
      n < 1 ? "The Epiphany" : "#{ordinal(n)} Sunday after the Epiphany"
    when :advent
      n = ((sunday - advent_sunday(sunday.year)).to_i / 7) + 1
      "#{ordinal(n)} Sunday in Advent"
    when :lent
      n = ((sunday - (easter - 42)).to_i / 7) + 1
      n.between?(1, 5) ? "#{ordinal(n)} Sunday in Lent" : "Sunday in Lent"
    when :easter
      n = ((sunday - easter).to_i / 7)
      "#{ordinal(n)} Sunday after Easter"
    when :pre_lent then "Sunday before Lent"
    else season(sunday, tradition: tradition).to_s.split("_").map(&:capitalize).join(" ")
    end
  end

  # =====================================================================
  # SANCTORAL CYCLE  (fixed-date feasts)
  # =====================================================================

  # Seeded with the BCP red-letter days. [month, day] => {name:, rank:}.
  # Christmas / Epiphany live in the temporal table as principal feasts.
  SANCTORAL = {
    [1, 1]   => { name: "The Circumcision of Christ", short: "The Circumcision", rank: :holy_day, event: true },
    [1, 25]  => { name: "Conversion of Saint Paul", short: "Conversion of St Paul", rank: :apostle, event: true, article: :the },
    [2, 2]   => { name: "The Presentation of Christ (Candlemas)", short: "Candlemas", rank: :holy_day, event: true, article: :none },
    [2, 24]  => { name: "Saint Matthias the Apostle", short: "Saint Matthias", rank: :apostle },
    [3, 25]  => { name: "The Annunciation of the B.V.M.", short: "The Annunciation", rank: :holy_day, event: true },
    [4, 25]  => { name: "Saint Mark the Evangelist", short: "Saint Mark", rank: :festival },
    [5, 1]   => { name: "Saint Philip and Saint James, Apostles", short: "SS Philip & James", rank: :apostle },
    [6, 11]  => { name: "Saint Barnabas the Apostle", short: "Saint Barnabas", rank: :apostle },
    [6, 24]  => { name: "The Nativity of Saint John the Baptist", short: "Nativity of St John Baptist", rank: :holy_day, event: true, article: :the },
    [6, 29]  => { name: "Saint Peter the Apostle", short: "Saint Peter", rank: :apostle },
    [7, 25]  => { name: "Saint James the Apostle", short: "Saint James", rank: :apostle },
    [8, 24]  => { name: "Saint Bartholomew the Apostle", short: "Saint Bartholomew", rank: :apostle },
    [9, 21]  => { name: "Saint Matthew, Apostle and Evangelist", short: "Saint Matthew", rank: :apostle },
    [9, 29]  => { name: "Saint Michael and All Angels", short: "Michaelmas", rank: :festival },
    [10, 18] => { name: "Saint Luke the Evangelist", short: "Saint Luke", rank: :festival },
    [10, 28] => { name: "Saint Simon and Saint Jude, Apostles", short: "SS Simon & Jude", rank: :apostle },
    [11, 1]  => { name: "All Saints", short: "All Saints", rank: :principal_feast, event: true },
    [11, 30] => { name: "Saint Andrew the Apostle", short: "Saint Andrew", rank: :apostle },
    [12, 21] => { name: "Saint Thomas the Apostle", short: "Saint Thomas", rank: :apostle },
    [12, 25] => { name: "Christmas Day", short: "Christmas", rank: :principal_feast, event: true },
    [12, 26] => { name: "Saint Stephen, Deacon and Martyr", short: "Saint Stephen", rank: :festival },
    [12, 27] => { name: "Saint John, Apostle and Evangelist", short: "Saint John", rank: :apostle },
    [12, 28] => { name: "The Holy Innocents", short: "Holy Innocents", rank: :festival, event: true }
  }.dup

  # Register your own feast. Highest-rank wins if a day is already taken;
  # otherwise it's kept as a co-commemoration.
  def add(month:, day:, name:, rank: :lesser_festival, short: nil, event: false)
    existing = entries_at(month, day)
    existing << { name: name, rank: rank, short: short || name, event: event }
    SANCTORAL[[month, day]] = existing.size == 1 ? existing.first : existing
    self
  end

  def entries_at(month, day)
    raw = SANCTORAL[[month, day]]
    return [] if raw.nil?
    raw.is_a?(Hash) ? [raw] : raw
  end

  def sanctoral(date)
    entries_at(date.month, date.day).map { |f| f.merge(kind: :sanctoral) }
  end

  # =====================================================================
  # PRECEDENCE / TRANSFER
  # =====================================================================

  Day = Struct.new(:date, :season, :principal, :commemorations, :transferred_in, keyword_init: true) do
    def label = principal[:name]
    def short_label = principal[:short] || principal[:name]
    def event? = principal[:event] == true
    def sanctoral? = principal[:kind] == :sanctoral

    def to_s
      base = "#{date} season=#{season} principal=#{principal[:name].inspect} (#{principal[:rank]})"
      base += " commemoration=#{commemorations.map { _1[:name] }.join('; ').inspect}" if commemorations.any?
      base += " transferred_in=#{transferred_in.map { _1[:name] }.join('; ').inspect}" if transferred_in.any?
      "#<Ordo::Day #{base}>"
    end
    alias_method :inspect, :to_s
  end

  def resolve(date, tradition: :traditional)
    temporal_obs = temporal(date, tradition: tradition)
    candidates = ([temporal_obs] + sanctoral(date)) + transferred_into(date, tradition)
    candidates.sort_by! { |c| rank_value(c[:rank]) }

    principal = candidates.first
    rest = candidates.drop(1)

    # A festival/apostle displaced by a *privileged season Sunday* or a
    # higher feast is transferred out, not merely commemorated.
    commemorations = []
    rest.each do |c|
      commemorations << c unless transfers_out?(c, principal, date, tradition)
    end

    Day.new(
      date: date,
      season: season(date, tradition: tradition),
      principal: principal,
      commemorations: commemorations,
      transferred_in: candidates.select { _1[:transferred] }
    )
  end

  # A sanctoral festival/apostle yields (and transfers) when the day's
  # principal is a principal feast, or a privileged-season Sunday.
  def transfers_out?(feast, principal, date, _tradition)
    return false unless feast[:kind] == :sanctoral
    return false if rank_value(feast[:rank]) <= rank_value(:festival) &&
                    principal[:kind] == :sanctoral # two saints: commemorate, don't transfer
    principal[:rank] == :principal_feast ||
      (principal[:kind] == :temporal && principal[:season] && SEASON_RANK[principal[:season]] == :privileged && principal[:sunday])
  end

  # Find feasts displaced from earlier days that land on `date` (the next
  # day free of an equal-or-higher observance). Looks back up to 8 days.
  def transferred_into(date, tradition)
    (1..8).each_with_object([]) do |back, acc|
      src = date - back
      sanctoral(src).each do |feast|
        next unless would_transfer_from?(src, feast, tradition)
        acc << feast.merge(transferred: true, from: src) if first_free_day(src, feast, tradition) == date
      end
    end
  end

  def would_transfer_from?(src, feast, tradition)
    principal = temporal(src, tradition: tradition)
    principal[:rank] == :principal_feast ||
      (SEASON_RANK[principal[:season]] == :privileged && principal[:sunday] &&
       rank_value(feast[:rank]) > rank_value(:festival).pred) # festival/apostle yields
  rescue StandardError
    false
  end

  def first_free_day(src, feast, tradition)
    d = src + 1
    8.times do
      p = temporal(d, tradition: tradition)
      blocked = p[:rank] == :principal_feast ||
                (SEASON_RANK[p[:season]] == :privileged && p[:sunday]) ||
                sanctoral(d).any? { |o| rank_value(o[:rank]) <= rank_value(feast[:rank]) }
      return d unless blocked
      d += 1
    end
    src + 1
  end

  # =====================================================================
  # FORMATTING HELPERS
  # =====================================================================

  def first_sunday_after(d)
    step = (7 - d.wday) % 7
    d + (step.zero? ? 7 : step)
  end

  def ordinal(n)
    %w[Zeroth First Second Third Fourth Fifth Sixth Seventh Eighth Ninth
       Tenth Eleventh Twelfth Thirteenth Fourteenth Fifteenth Sixteenth
       Seventeenth Eighteenth Nineteenth Twentieth Twenty-first Twenty-second
       Twenty-third Twenty-fourth Twenty-fifth Twenty-sixth Twenty-seventh][n] || "#{n}th"
  end

  SEASON_NAME = {
    advent: "Advent", christmas: "Christmastide", epiphany: "Epiphanytide",
    pre_lent: "Pre-Lent", lent: "Lent", easter: "Eastertide", trinity: "Trinity"
  }.freeze

  # =====================================================================
  # TIMESTAMP FORMATTING
  # =====================================================================
  #
  # Ordo::Format.stamp(date, style: :feast)
  #
  #   :season   — terse, season only      -> "Eastertide, A.D. 2026"
  #   :feast    — the day's observance     -> "Saint John, A.D. 2026"
  #   :almanac  — feast over season + computus
  #              -> "Saint John the Evangelist
  #                  Christmastide · A.D. 2026 · g IV · DL d"
  #   :colophon — old-book dateline        -> "on the feast of Saint Andrew,
  #                                            in the year of grace 2026"
  #
  module Format
    module_function

    def stamp(date, style: :feast, tradition: :traditional)
      day = Ordo.resolve(date, tradition: tradition)
      case style
      when :season   then "#{Ordo::SEASON_NAME[day.season]}, A.D. #{date.year}"
      when :feast    then "#{day.short_label}, A.D. #{date.year}"
      when :almanac  then almanac(date, day)
      when :colophon then colophon(date, day)
      else day.short_label
      end
    end

    def almanac(date, day)
      season = Ordo::SEASON_NAME[day.season]
      computus = "g #{Ordo.roman(golden_number(date.year))} · DL #{dominical_letter(date.year)}"
      "#{day.label}\n#{season} · A.D. #{date.year} · #{computus}"
    end

    def colophon(date, day)
      lede =
        if !day.sanctoral?
          "on #{day.short_label}"
        elsif day.event?
          art = article_for(day)
          "on #{art}#{day.short_label.sub(/\AThe /, "")}"
        else
          "on the feast of #{day.short_label}"
        end
      "#{lede}, in the year of grace #{date.year}"
    end

    # Explicit :article wins; otherwise guess from a leading "The".
    def article_for(day)
      case day.principal[:article]
      when :the  then "the "
      when :none then ""
      else day.label.start_with?("The ") ? "the " : ""
      end
    end

    # Golden number: year's place in the 19-year Metonic cycle.
    def golden_number(year) = (year % 19) + 1

    # Sunday Letter (dominical letter) for a Gregorian year.
    def dominical_letter(year)
      # Letter of the first Sunday; leap years carry two — return the
      # letter in force from March onward (the common convention for a stamp).
      jan1 = Date.new(year, 1, 1).wday # 0 = Sunday
      idx = (7 - jan1) % 7             # days until first Sunday
      letters = %w[A G F E D C B]      # A if Jan 1 is Sunday, etc.
      letters[(7 - idx) % 7]
    end
  end

  def roman(n)
    map = { 10 => "X", 9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }
    out = +""
    rem = n
    map.each { |v, s| (out << s; rem -= v) while rem >= v }
    out
  end
end

class Date
  def ordo(tradition: :traditional)
    Ordo.resolve(self, tradition: tradition)
  end

  def liturgical_season(tradition: :traditional)
    Ordo.season(self, tradition: tradition)
  end

  # The day's principal observance, as a string — what you'd put in a timestamp.
  def liturgical_label(tradition: :traditional)
    ordo(tradition: tradition).label
  end

  # A formatted timestamp. style: :season | :feast | :almanac | :colophon
  def liturgical_stamp(style: :feast, tradition: :traditional)
    Ordo::Format.stamp(self, style: style, tradition: tradition)
  end
end