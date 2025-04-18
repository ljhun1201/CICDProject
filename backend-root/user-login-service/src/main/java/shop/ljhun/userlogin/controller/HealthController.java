package shop.ljhun.userlogin.controller;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {

    @GetMapping("/healthz")
    public ResponseEntity<String> generalHealthCheck(HttpServletRequest request) {
        return ResponseEntity.ok("OK");
    }
}