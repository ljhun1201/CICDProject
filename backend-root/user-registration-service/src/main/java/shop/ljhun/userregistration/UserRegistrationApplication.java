// Spring Boot MVC + Repository + Service + Model 구조 (JPA 제거, 순수 JDBC 기반)

// ✅ Application 진입점(개조)

package shop.ljhun.userregistration;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@SpringBootApplication
public class UserRegistrationApplication {
    public static void main(String[] args) {
        SpringApplication.run(UserRegistrationApplication.class, args);
    }

    @Bean
    public WebMvcConfigurer corsConfigurer() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/**")
                    .allowedOrigins(
                        "https://www.ljhun.shop", 
                        "https://ljhun.shop"
                    )
                    .allowedMethods("GET", "POST", "OPTIONS")
                    .allowedHeaders("content-type", "authorization")
                    .allowCredentials(true);
            }
        };
    }
}


/*
package com.example.userregistration;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@SpringBootApplication
public class UserRegistrationApplication {
    public static void main(String[] args) {
        SpringApplication.run(UserRegistrationApplication.class, args);
    }

    // @Bean: Spring Boot가 자동으로 관리해주는 객체, Bean으로 들어가야 Spring Boot가 생성, 주입, 생명주기 관리 등을 해줌
    // CORS 설정, @Bean 없이 오버라이딩만 하면 Spring은 그 객체를 모른다. 즉, Spring이 관리하는 설정에 반영되지 않는다.
    @Bean
    public WebMvcConfigurer corsConfigurer() {
        return new WebMvcConfigurer() {
            @Override
            public void addCorsMappings(CorsRegistry registry) {
                registry.addMapping("/**")
                        .allowedOrigins("*")
                        .allowedMethods("GET", "POST", "OPTIONS");
            }
        };
    }
}

// ✅ Controller
package com.example.userregistration.controller;

import com.example.userregistration.model.User;
import com.example.userregistration.service.UserService;
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

    //@Valid, @RequestBody 객체는 자동 바인딩(자동 관리)이지만, 매번 HTTP 요청마다 새로 만들어지는 DTO (Data Transfer Object) 이기 때문에 @Autowired처럼 Bean으로 주입되는 DI 대상은 아님.
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

    @GetMapping("/healthz")
    public ResponseEntity<?> generalHealthCheck(HttpServletRequest request) {
        System.out.println("Health check received from: " + request.getHeader("X-Forwarded-For"));
        System.out.println("User-Agent: " + request.getHeader("User-Agent"));
        return ResponseEntity.ok("OK");
    }
}

// ✅ Model
package com.example.userregistration.model;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public class User {

    @NotBlank(message = "username은 필수입니다.")
    private String username;

    @NotBlank(message = "password는 필수입니다.")
    @Pattern(
        regexp = "^(?=.*[a-z])(?=.*\\d)(?=.*[!@#$%^&*()_+=-]).{8,}$",
        message = "비밀번호는 8자 이상이며, 소문자, 숫자, 특수문자를 포함해야 합니다."
    )
    private String password;

    @NotBlank(message = "email은 필수입니다.")
    @Email(message = "유효한 이메일 형식이어야 합니다.")
    private String email;

    // Getter & Setter
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
}

// ✅ Repository
package com.example.userregistration.repository;

import com.example.userregistration.model.User;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

import java.sql.*;

@Repository
public class UserRepository {

    // DI: Bean에서의 하나의 주입 매커니즘, 외부에서의 값을 자동으로 관리해줌(우선순위 1. 환경변수, 2. application.properties에서의 변수, 3. localhost 사용)
    @Value("${DB_HOST:localhost}")
    private String dbHost;

    @Value("${DB_USER:root}")
    private String dbUser;

    @Value("${DB_PASSWORD:pass1234}")
    private String dbPassword;

    @Value("${DB_NAME:userdb}")
    private String dbName;

    public boolean existsByUsername(String username) {
        try (Connection conn = getConnection();
             PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM users WHERE username = ?")) {

            stmt.setString(1, username);
            ResultSet rs = stmt.executeQuery();
            return rs.next() && rs.getInt(1) > 0;

        } catch (SQLException e) {
            e.printStackTrace();
            return false;
        }
    }

    public void save(User user) {
        try (Connection conn = getConnection();
             PreparedStatement stmt = conn.prepareStatement(
                     "INSERT INTO users (username, password, email) VALUES (?, ?, ?)")) {

            stmt.setString(1, user.getUsername());
            stmt.setString(2, user.getPassword());
            stmt.setString(3, user.getEmail());
            stmt.executeUpdate();

        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private Connection getConnection() throws SQLException {
        return DriverManager.getConnection(
                "jdbc:mysql://" + dbHost + ":3306/" + dbName, dbUser, dbPassword);
    }
}

// ✅ Service
package com.example.userregistration.service;

import com.example.userregistration.model.User;
import com.example.userregistration.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    public boolean isUsernameTaken(String username) {
        return userRepository.existsByUsername(username);
    }

    public void registerUser(User user) {
        userRepository.save(user);
    }
}
*/
/*
용어	설명
Bean	Spring Container에 등록된 객체 (자동 관리 대상)
DI	    Spring이 필요할 때 Bean을 알아서 주입해주는 기능(우선순위 1. 환경변수, 2. application.properties에서의 변수, 3. localhost 사용)
DI가 되기 위한 조건:	주입 대상이 반드시 Bean이어야 함
DI 방식: 1. Value, 2. AutoWired
------------------------------

Bean으로 만드는 방법:
컴포넌트 스캔	@Component, @Service, @Repository, @Controller
명시적 등록	    @Bean in @Configuration 클래스
------------------------------

@Valid, @RequestBody 또한 자동 관리 기능이지만, HTTP 요청에 의해 오는 것이므로 DI는 아님.
@Valid: 자동 유효성 검증(@NotBlank, @Pattern, @Email 등을 기준으로 자동 검증)
@RequestBody: MVC에서 Controller에서 Model에 자동 바인딩
*/