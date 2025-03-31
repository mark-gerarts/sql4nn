import torch
from torch import nn
from torch import optim
import os


class ReLUFNN(nn.Module):
    def __init__(
        self, input_size=1, hidden_size=4, num_hidden_layers=10, output_size=1
    ):
        super().__init__()
        layers = []

        layers.append(nn.Linear(input_size, hidden_size))
        layers.append(nn.ReLU())

        for _ in range(num_hidden_layers - 1):
            layers.append(nn.Linear(hidden_size, hidden_size))
            layers.append(nn.ReLU())

        layers.append(nn.Linear(hidden_size, output_size))

        self.linear_relu_stack = nn.Sequential(*layers)

    def forward(self, x):
        return self.linear_relu_stack(x)


def train(model, x_train, y_train, epochs=1000, save_path=None):
    if save_path and os.path.exists(save_path):
        model.load_state_dict(torch.load(save_path, weights_only=True))
        return

    criterion = nn.MSELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.01)

    x_train_tensor = ensure_tensor(x_train).unsqueeze(1)
    y_train_tensor = ensure_tensor(y_train).unsqueeze(1)

    num_epochs = epochs
    for _ in range(num_epochs):
        model.train()
        optimizer.zero_grad()
        outputs = model(x_train_tensor)
        loss = criterion(outputs, y_train_tensor)
        loss.backward()
        optimizer.step()

    if save_path:
        torch.save(model.state_dict(), save_path)


def ensure_tensor(tensor_or_array):
    if torch.is_tensor(tensor_or_array):
        return tensor_or_array
    else:
        return torch.tensor(tensor_or_array, dtype=torch.float32)
