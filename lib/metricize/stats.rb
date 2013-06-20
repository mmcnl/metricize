module Metricize
  module Stats

    def sum
      return self.inject(0){|accum, i| accum + i }
    end

    def mean
      return self.sum / self.length.to_f
    end

    def sample_variance
      m = self.mean
      sum = self.inject(0){|accum, i| accum + (i - m) ** 2 }
      return sum / (self.length - 1).to_f
    end

    def standard_deviation
      return Math.sqrt(self.sample_variance)
    end

    def calculate_percentile(percentile)
      return self.first if self.size == 1
      values_sorted = self.sort
      k = (percentile*(values_sorted.length-1)+1).floor - 1
      values_sorted[k]
    end

  end
end
