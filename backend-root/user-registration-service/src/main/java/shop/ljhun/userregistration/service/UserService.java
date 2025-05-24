package shop.ljhun.userregistration.service;

import shop.ljhun.userregistration.model.User;
import shop.ljhun.userregistration.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class UserService {

    //int i = 0;

    @Autowired
    private UserRepository userRepository;

    public boolean isUsernameTaken(String username) {
        return userRepository.existsByUsername(username);
    }

    public void registerUser(User user) {
        userRepository.save(user);
    }
}