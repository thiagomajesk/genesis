defmodule Genesis.Bloom do
  @moduledoc false

  import Bitwise

  # Max number of hash functions to use
  @hash_count 6

  # We want to target 1% false positives
  @target_rate 0.01

  # Returns how many bits do we need to represent n elements
  # The formula was derived from the Wikipedia page on bloom filters:
  # https://en.wikipedia.org/wiki/Bloom_filter#Probability_of_false_positives
  def bloom_bits(n) do
    single_hash_rate = :math.pow(@target_rate, 1 / @hash_count)
    ceil(-@hash_count * n / :math.log(1 - single_hash_rate))
  end

  # Merges two bloom filter bit masks into one.
  # (just so we don't have to import Bitwise everywhere)
  def merge_masks(mask1, mask2), do: mask1 ||| mask2

  def merge_masks(masks) when is_list(masks) do
    Enum.reduce(masks, 0, fn mask, acc -> merge_masks(acc, mask) end)
  end

  # Returns the positions for the bloom filter as a bit mask
  def bloom_mask({term1, term2}, bits) do
    Enum.reduce(0..(@hash_count - 1), 0, fn i, acc ->
      acc ||| 1 <<< :erlang.phash2({term1, term2, i}, bits)
    end)
  end
end
