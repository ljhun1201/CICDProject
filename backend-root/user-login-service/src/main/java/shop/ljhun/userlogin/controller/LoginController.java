package shop.ljhun.userlogin.controller;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import shop.ljhun.userlogin.model.User;
import shop.ljhun.userlogin.service.UserService;

import java.util.Map;

@RestController
@RequestMapping("/app-two")
public class LoginController {

    @Autowired
    private UserService userService;

    @GetMapping("/login")
    public ResponseEntity<?> loginHealthCheck(HttpServletRequest request) {
        return ResponseEntity.ok(Map.of("success", true, "message", "Health Check Passed"));
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody Map<String, String> payload) {
        String username = payload.get("username");
        String password = payload.get("password");

        if (username == null || password == null) {
            return ResponseEntity.badRequest().body(Map.of("success", false, "error", "Missing fields"));
        }

        boolean valid = userService.verifyLogin(username, password);
        if (valid) {
            return ResponseEntity.ok(Map.of("success", true, "message", "Login Succeed"));
        } else {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("success", false, "error", "Invalid credentials"));
        }
    }

    @RequestMapping(value = "/login", method = RequestMethod.OPTIONS)
    public ResponseEntity<?> handleOptions() {
        return ResponseEntity.ok(Map.of("message", "CORS preflight passed"));
    }
}