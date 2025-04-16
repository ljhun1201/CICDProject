package shop.ljhun.userregistration.model;

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

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }
}