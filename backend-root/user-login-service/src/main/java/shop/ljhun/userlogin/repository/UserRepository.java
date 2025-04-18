package shop.ljhun.userlogin.repository;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Repository;

import java.sql.*;

@Repository
public class UserRepository {

    @Value("${DB_HOST:localhost}")
    private String dbHost;

    @Value("${DB_USER:root}")
    private String dbUser;

    @Value("${DB_PASSWORD:pass1234}")
    private String dbPassword;

    @Value("${DB_NAME:userdb}")
    private String dbName;

    private Connection getConnection() throws SQLException {
        return DriverManager.getConnection(
                "jdbc:mysql://" + dbHost + ":3306/" + dbName, dbUser, dbPassword);
    }

    public boolean verifyCredentials(String username, String password) {
        String sql = "SELECT 1 FROM users WHERE username = ? AND password = ?";
        try (Connection conn = getConnection();
             PreparedStatement stmt = conn.prepareStatement(sql)) {

            stmt.setString(1, username);
            stmt.setString(2, password);
            ResultSet rs = stmt.executeQuery();
            return rs.next();

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
}