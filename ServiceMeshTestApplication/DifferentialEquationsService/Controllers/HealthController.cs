using Microsoft.AspNetCore.Mvc;

namespace IntegrationService.Controllers;

[ApiController]
[Route("health")]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult GetHealth()
    {
        return Ok(new
        {
            service = "DifferentialService",
            status = "healthy",
            timestamp = DateTime.UtcNow
        });
    }
}