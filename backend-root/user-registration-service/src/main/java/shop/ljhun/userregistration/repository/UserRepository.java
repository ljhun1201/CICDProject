package shop.ljhun.userregistration.repository;

import shop.ljhun.userregistration.model.User;
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