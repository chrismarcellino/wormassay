/*
* Copyright 2016 Nu-book Inc.
* Copyright 2016 ZXing authors
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

#include "ODRSS14Reader.h"
#include "rss/ODRSSReaderHelper.h"
#include "rss/ODRSSPair.h"
#include "BitArray.h"
#include "GTIN.h"
#include "Result.h"
#include "DecodeHints.h"
#include "ZXConfig.h"
#include "ZXContainerAlgorithms.h"

#include <list>
#include <array>
#include <algorithm>
#include <numeric>
#include <sstream>
#include <iomanip>

namespace ZXing {
namespace OneD {

static const int OUTSIDE_EVEN_TOTAL_SUBSET[] = { 1,10,34,70,126 };
static const int INSIDE_ODD_TOTAL_SUBSET[] = { 4,20,48,81 };
static const int OUTSIDE_GSUM[] = { 0,161,961,2015,2715 };
static const int INSIDE_GSUM[] = { 0,336,1036,1516 };
static const int OUTSIDE_ODD_WIDEST[] = { 8,6,4,3,1 };
static const int INSIDE_ODD_WIDEST[] = { 2,4,6,8 };

using namespace RSS;

static const std::array<FinderCounters, 9> FINDER_PATTERNS = {
	3,8,2,1,
	3,5,5,1,
	3,3,7,1,
	3,1,9,1,
	2,7,4,1,
	2,5,6,1,
	2,3,8,1,
	1,5,7,1,
	1,3,9,1,
};

struct RSS14DecodingState : public RowReader::DecodingState
{
	std::list<RSS::Pair> possibleLeftPairs;
	std::list<RSS::Pair> possibleRightPairs;
};

static BitArray::Range
FindFinderPattern(const BitArray& row, bool rightFinderPattern, FinderCounters& counters)
{
	if (row.size() < 2 * 18 + 14)
		return {row.end(), row.end()};

	return RowReader::FindPattern(
	    // Will encounter white first when searching for right finder pattern
		// The finder pattern is inside the code, i.e. there must be at least 18 pixels on both sides
		row.getNextSetTo(row.iterAt(18), !rightFinderPattern), row.end(), counters,
		[&](BitArray::Iterator b, BitArray::Iterator e, const FinderCounters& counters) {
			// The finder pattern must have more pixels left and right that it is wide.
			return ReaderHelper::IsFinderPattern(counters) && (b - row.begin()) > (e - b) && (row.end() - e) > (e-b);
		});
}

static RSS::FinderPattern
ParseFoundFinderPattern(const BitArray& row, int rowNumber, bool right, BitArray::Range range, FinderCounters& finderCounters)
{
	if (!range || range.begin == row.begin())
		return {};

	// Actually we found elements 2-5 -> Locate element 1
	auto i = std::find(BitArray::ReverseIterator(range.begin), row.rend(), *range.begin);
	int firstCounter = static_cast<int>(range.begin - i.base());
	range.begin = i.base();

	// Make 'counters' hold 1-4
	std::copy_backward(finderCounters.begin(), finderCounters.end() - 1, finderCounters.end());
	finderCounters[0] = firstCounter;
	int value = RSS::ReaderHelper::ParseFinderValue(finderCounters, FINDER_PATTERNS);
	if (value < 0)
		return {};

	int start = static_cast<int>(range.begin - row.begin());
	int end = static_cast<int>(range.end - row.begin());
	if (right) {
		// row is actually reversed
		start = row.size() - 1 - start;
		end = row.size() - 1 - end;
	}

	return {value,
			static_cast<int>(range.begin - row.begin()),
			static_cast<int>(range.end - row.begin()),
			{ResultPoint(start, rowNumber), ResultPoint(end, rowNumber)}};
}

static RSS::DataCharacter
DecodeDataCharacter(const BitArray& row, const RSS::FinderPattern& pattern, bool outsideChar)
{
	DataCounters oddCounts, evenCounts;

	if (!ReaderHelper::ReadOddEvenElements(row, pattern, outsideChar ? 16 : 15, outsideChar, oddCounts, evenCounts))
		return {};

	auto calcChecksumPortion = [](const std::array<int, 4>& counts) {
		int res = 0;
		for (auto it = counts.rbegin(); it != counts.rend(); ++it) {
			res = 9 * res + *it;
		}
		return res;
	};

	int checksumPortion = calcChecksumPortion(oddCounts) + 3 * calcChecksumPortion(evenCounts);
	int oddSum = Reduce(oddCounts);
	int evenSum = Reduce(evenCounts);

	if (outsideChar) {
		if ((oddSum & 1) != 0 || oddSum > 12 || oddSum < 4) {
			return {};
		}
		int group = (12 - oddSum) / 2;
		int oddWidest = OUTSIDE_ODD_WIDEST[group];
		int evenWidest = 9 - oddWidest;
		int vOdd = RSS::ReaderHelper::GetRSSvalue(oddCounts, oddWidest, false);
		int vEven = RSS::ReaderHelper::GetRSSvalue(evenCounts, evenWidest, true);
		int tEven = OUTSIDE_EVEN_TOTAL_SUBSET[group];
		int gSum = OUTSIDE_GSUM[group];
		return {vOdd * tEven + vEven + gSum, checksumPortion};
	}
	else {
		if ((evenSum & 1) != 0 || evenSum > 10 || evenSum < 4) {
			return {};
		}
		int group = (10 - evenSum) / 2;
		int oddWidest = INSIDE_ODD_WIDEST[group];
		int evenWidest = 9 - oddWidest;
		int vOdd = RSS::ReaderHelper::GetRSSvalue(oddCounts, oddWidest, true);
		int vEven = RSS::ReaderHelper::GetRSSvalue(evenCounts, evenWidest, false);
		int tOdd = INSIDE_ODD_TOTAL_SUBSET[group];
		int gSum = INSIDE_GSUM[group];
		return {vEven * tOdd + vOdd + gSum, checksumPortion};
	}

}

static RSS::Pair
DecodePair(const BitArray& row, bool right, int rowNumber)
{
	FinderCounters finderCounters = {};

	auto range = FindFinderPattern(row, right, finderCounters);
	auto pattern = ParseFoundFinderPattern(row, rowNumber, right, range, finderCounters);
	if (pattern.isValid()) {
		auto outside = DecodeDataCharacter(row, pattern, true);
		if (outside.isValid()) {
			auto inside = DecodeDataCharacter(row, pattern, false);
			if (inside.isValid()) {
				return {1597 * outside.value() + inside.value(), outside.checksumPortion() + 4 * inside.checksumPortion(), pattern};
			}
		}
	}
	return {};
}

static void
AddOrTally(std::list<RSS::Pair>& possiblePairs, const RSS::Pair& pair)
{
	if (!pair.isValid()) {
		return;
	}
	for (RSS::Pair& other : possiblePairs) {
		if (other == pair) {
			other.incrementCount();
			return;
		}
	}
	possiblePairs.push_back(pair);
}

static bool
CheckChecksum(const RSS::Pair& leftPair, const RSS::Pair& rightPair)
{
	int checkValue = (leftPair.checksumPortion() + 16 * rightPair.checksumPortion()) % 79;
	int targetCheckValue =
		9 * leftPair.finderPattern().value() + rightPair.finderPattern().value();
	if (targetCheckValue > 72) {
		targetCheckValue--;
	}
	if (targetCheckValue > 8) {
		targetCheckValue--;
	}
	return checkValue == targetCheckValue;
}

static Result
ConstructResult(const RSS::Pair& leftPair, const RSS::Pair& rightPair)
{
	int64_t symbolValue = 4537077 * static_cast<int64_t>(leftPair.value()) + rightPair.value();
	std::wstringstream buffer;
	buffer << std::setw(13) << std::setfill(L'0') << symbolValue;
	buffer.put(GTIN::ComputeCheckDigit(buffer.str()));

	auto& leftPoints = leftPair.finderPattern().points();
	auto& rightPoints = rightPair.finderPattern().points();
	return Result(buffer.str(), { leftPoints[0], leftPoints[1], rightPoints[0], rightPoints[1] }, BarcodeFormat::RSS_14);
}

Result
RSS14Reader::decodeRow(int rowNumber, const BitArray& row_, std::unique_ptr<DecodingState>& state) const
{
	if (!state) {
		state.reset(new RSS14DecodingState);
	}
	auto* prevState = static_cast<RSS14DecodingState*>(state.get());

	BitArray row = row_.copy();
	AddOrTally(prevState->possibleLeftPairs, DecodePair(row, false, rowNumber));
	row.reverse();
	AddOrTally(prevState->possibleRightPairs, DecodePair(row, true, rowNumber));

	// To be able to detect "stacked" RSS codes (split over multiple lines)
	// we need to store the parts we found and try all possible left/right
	// combinations. To prevent lots of false positives, we require each
	// pair to have been seen in at least two lines.
	for (const auto& left : prevState->possibleLeftPairs) {
		if (left.count() > 1) {
			for (const auto& right : prevState->possibleRightPairs) {
				if (right.count() > 1) {
					if (CheckChecksum(left, right)) {
						return ConstructResult(left, right);
					}
				}
			}
		}
	}
	return Result(DecodeStatus::NotFound);
}

Result RSS14Reader::decodePattern(int, const PatternView& row, std::unique_ptr<RowReader::DecodingState>&) const
{
#ifdef ZX_USE_NEW_ROW_READERS
	return FindFinderPattern<false>(row).isValid() ? Result(DecodeStatus::_internal) : Result(DecodeStatus::NotFound);
#else
	return Result(DecodeStatus::NotFound);
#endif
}

} // OneD
} // ZXing
