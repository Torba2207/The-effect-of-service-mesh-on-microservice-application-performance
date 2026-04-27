using Microsoft.AspNetCore.Mvc;

namespace PermutationService.Controllers;

[ApiController]
[Route("health")]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult GetHealth()
    {
        return Ok(new
        {
            service = "PermutationService",
            status = "healthy",
            timestamp = DateTime.UtcNow
        });
    }
}