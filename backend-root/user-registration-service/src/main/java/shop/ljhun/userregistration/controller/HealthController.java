@RestController
public class HealthController {

    @GetMapping("/healthz")
    public ResponseEntity<String> generalHealthCheck(HttpServletRequest request) {
        return ResponseEntity.ok("OK");
    }
}