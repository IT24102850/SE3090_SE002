namespace SmeBackend.Models;

public class DynamicForm : BaseEntity, ITenantScoped
{
    public Guid TenantId { get; set; }
    public string FormType { get; set; } = string.Empty;
    public string SchemaJson { get; set; } = string.Empty;
    public string? UiSchemaJson { get; set; }
    public string? ValidationRulesJson { get; set; }
}