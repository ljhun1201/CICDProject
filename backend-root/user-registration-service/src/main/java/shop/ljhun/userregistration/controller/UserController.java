package shop.ljhun.userregistration.controller;

import shop.ljhun.userregistration.model.User;
import shop.ljhun.userregistration.service.UserService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/app-one")
public class UserController {

    @Autowired
    private UserService userService;

    @GetMapping("/register")
    public ResponseEntity<?> registerHealthCheck(HttpServletRequest request) {
        System.out.println("Health check received from: " + request.getHeader("X-Forwarded-For"));
        System.out.println("User-Agent: " + request.getHeader("User-Agent"));
        return ResponseEntity.ok(Map.of("success", true, "message", "Health Check Passed"));
    }

    @PostMapping("/register")
    public ResponseEntity<?> registerUser(@Valid @RequestBody User user, BindingResult bindingResult) {
        if (bindingResult.hasErrors()) {
            String errorMsg = bindingResult.getFieldError().getDefaultMessage();
            return ResponseEntity.badRequest().body(Map.of("success", false, "error", errorMsg));
        }

        if (userService.isUsernameTaken(user.getUsername())) {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(Map.of("success", false, "error", "Username already exists"));
        }

        userService.registerUser(user);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(Map.of("success", true, "message", "User registered successfully"));
    }

    @GetMapping(path = "/healthz")
    public ResponseEntity<?> generalHealthCheck(HttpServletRequest request) {
        System.out.println("Health check received from: " + request.getHeader("X-Forwarded-For"));
        System.out.println("User-Agent: " + request.getHeader("User-Agent"));
        return ResponseEntity.ok("OK");
    }
}