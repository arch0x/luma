#include <iostream>
#include <string>
#include <vector>

int main() {
    const std::vector<std::string> titles{"Design notes", "Lab notes"};
    for (const auto& title : titles) {
        std::cout << title << '\n';
    }
}
