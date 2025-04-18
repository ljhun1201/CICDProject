package shop.ljhun.userlogin.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import shop.ljhun.userlogin.repository.UserRepository;

@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;

    public boolean verifyLogin(String username, String password) {
        return userRepository.verifyCredentials(username, password);
    }
}