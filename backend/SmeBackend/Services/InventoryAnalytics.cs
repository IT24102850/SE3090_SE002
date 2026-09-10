namespace SmeBackend.Services;

public sealed record DemandPredictionResult(
    decimal AverageDailyDemand,
    decimal PredictedTotalDemand,
    decimal SafetyStock,
    decimal Confidence);

public sealed record StockAdjustmentResult(
    decimal RecommendedQuantity,
    decimal SafetyBuffer,
    decimal MinimumToReorder,
    decimal TotalCost,
    string Priority);

public static class InventoryDemandPrediction
{
    public static DemandPredictionResult Predict(
        IEnumerable<decimal> usageValues,
        int forecastDays = 7,
        int leadTimeDays = 7,
        int safetyStockDays = 7)
    {
        if (usageValues is null)
        {
            throw new ArgumentNullException(nameof(usageValues));
        }

        var values = usageValues.ToList();
        if (values.Count == 0)
        {
            throw new ArgumentException("Usage history cannot be empty.", nameof(usageValues));
        }

        if (forecastDays < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(forecastDays), "Forecast days must be positive.");
        }

        if (leadTimeDays < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(leadTimeDays), "Lead time days must be positive.");
        }

        if (safetyStockDays < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(safetyStockDays), "Safety stock days cannot be negative.");
        }

        var averageDailyDemand = values.Average();
        var predictedTotalDemand = averageDailyDemand * forecastDays;
        var safetyStock = averageDailyDemand * safetyStockDays;
        var rawConfidence = 0.70m + Math.Min(0.25m, (decimal)values.Count / 50m);
        var confidence = rawConfidence < 0.55m
            ? 0.55m
            : rawConfidence > 0.99m
                ? 0.99m
                : rawConfidence;

        return new DemandPredictionResult(
            averageDailyDemand,
            predictedTotalDemand,
            safetyStock,
            confidence);
    }
}

public static class InventoryStockAdjustment
{
    public static StockAdjustmentResult Calculate(
        decimal currentStock,
        decimal reorderLevel,
        decimal predictedDemand,
        int leadTimeDays = 7,
        int safetyStockDays = 7,
        decimal unitCost = 0m,
        int? orderMultiple = null,
        decimal? budgetLimit = null)
    {
        if (leadTimeDays < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(leadTimeDays), "Lead time days must be positive.");
        }

        if (safetyStockDays < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(safetyStockDays), "Safety stock days cannot be negative.");
        }

        if (unitCost < 0m)
        {
            throw new ArgumentOutOfRangeException(nameof(unitCost), "Unit cost cannot be negative.");
        }

        if (orderMultiple is < 1)
        {
            throw new ArgumentOutOfRangeException(nameof(orderMultiple), "Order multiple, when specified, must be at least 1.");
        }

        if (budgetLimit is < 0m)
        {
            throw new ArgumentOutOfRangeException(nameof(budgetLimit), "Budget limit cannot be negative.");
        }

        var safetyBuffer = Math.Max(0m, predictedDemand * ((decimal)safetyStockDays / Math.Max(1, leadTimeDays)));
        var recommendedQuantity = Math.Max(0m, predictedDemand + safetyBuffer - currentStock);
        var minimumToReorder = Math.Max(0m, reorderLevel - currentStock);

        if (recommendedQuantity < minimumToReorder)
        {
            recommendedQuantity = minimumToReorder;
        }

        if (orderMultiple.HasValue && orderMultiple.Value > 0)
        {
            recommendedQuantity = decimal.Ceiling(recommendedQuantity / orderMultiple.Value) * orderMultiple.Value;
        }

        var totalCost = recommendedQuantity * unitCost;
        if (budgetLimit.HasValue && totalCost > budgetLimit.Value)
        {
            throw new InvalidOperationException($"Total PO cost {totalCost:F2} exceeds budget limit {budgetLimit.Value:F2}.");
        }

        var priority = recommendedQuantity >= reorderLevel
            ? "high"
            : currentStock <= reorderLevel * 0.5m
                ? "critical"
                : "medium";

        return new StockAdjustmentResult(
            Math.Max(0m, recommendedQuantity),
            safetyBuffer,
            minimumToReorder,
            totalCost,
            priority);
    }
}
