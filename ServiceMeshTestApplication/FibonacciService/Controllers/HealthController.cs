using Microsoft.AspNetCore.Mvc;

namespace FibonacciService.Controllers;

[ApiController]
[Route("health")]
public class HealthController : ControllerBase
{
    [HttpGet]
    public IActionResult GetHealth()
    {
        return Ok(new
        {
            service = "FibonacciService",
            status = "healthy",
            timestamp = DateTime.UtcNow
        });
    }
}