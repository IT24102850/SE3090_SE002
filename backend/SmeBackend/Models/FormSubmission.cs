namespace SmeBackend.Models;

public class FormSubmission : BaseEntity
{
    public Guid? DynamicFormId { get; set; }
    public DynamicForm? DynamicForm { get; set; }
    public Guid EntityId { get; set; }
    public string DataJson { get; set; } = string.Empty;
    public DateTime SubmittedAt { get; set; } = DateTime.UtcNow;
}